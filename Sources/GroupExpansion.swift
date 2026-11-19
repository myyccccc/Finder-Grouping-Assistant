import AppKit
import ApplicationServices

/// Finder's icon view shows one row per group and a "Show All (n)" button on each group header.
/// Finder does not remember the expanded state, so each visit to a grouped folder starts collapsed.
/// The header button carries the identifier `groupDisclosureButton` in every language; a collapsed
/// group's title includes the item count, an expanded one ("Show Less") has no digits.
enum FinderGroupExpander {
    static let identifier = "groupDisclosureButton"

    static func isCollapsed(title: String) -> Bool {
        title.rangeOfCharacter(from: .decimalDigits) != nil
    }

    /// Expands every collapsed group in Finder's focused window. Finder only exposes the headers
    /// of groups that are on screen, so the view is stepped down a page at a time and returned to
    /// where it was afterwards. Stops as soon as Finder leaves the front or the user starts
    /// interacting; `finished` is false when it had to stop early. With `scrolls` false only the
    /// groups already on screen are opened and the view is never moved.
    @discardableResult
    static func expandAll(timeout: TimeInterval = 1.0, limit: TimeInterval = 8, scrolls: Bool = true) -> (expanded: Int, finished: Bool) {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return (0, false) }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let started = Date()
        var deadline = started.addingTimeInterval(timeout)
        var expanded = 0
        var sawButtons = false
        var scrollBar: AXUIElement?
        var startOffset: Double?
        func finish(_ done: Bool) -> (expanded: Int, finished: Bool) {
            if let scrollBar, let startOffset { set(scrollBar, offset: startOffset) }
            return (expanded, done)
        }
        while Date().timeIntervalSince(started) < limit {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
                  !FinderWindowProbe.userIsInteracting,
                  let window = element(app, kAXFocusedWindowAttribute) else { return finish(false) }
            var buttons: [AXUIElement] = []
            collect(window, depth: 0, into: &buttons)
            if !buttons.isEmpty { sawButtons = true }
            // Expanding a group pushes the ones below it down and Finder briefly disables their
            // buttons; the lowest visible group goes first so the others stay where they are.
            let collapsed = buttons.filter { isCollapsed(title: title(of: $0)) }.sorted { top(of: $0) > top(of: $1) }
            if let button = collapsed.first(where: { (value(of: $0, kAXEnabledAttribute) as Bool?) != false }) {
                guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return finish(false) }
                expanded += 1
                deadline = Date().addingTimeInterval(timeout)
                usleep(150_000)
                continue
            }
            if !collapsed.isEmpty {
                if Date() > deadline { return finish(false) }
                usleep(150_000)
                continue
            }
            // Groups appear a moment after Finder applies them.
            if !sawButtons {
                if Date() > deadline { return finish(true) }
                usleep(150_000)
                continue
            }
            // Everything on screen is open: move down a page, or stop at the bottom.
            guard scrolls else { return finish(true) }
            if scrollBar == nil, let area = groupScrollArea(in: window), let bar = element(area, kAXVerticalScrollBarAttribute) {
                scrollBar = bar
                startOffset = offset(of: bar)
            }
            guard let bar = scrollBar, let current = offset(of: bar), current < 0.999,
                  let area = groupScrollArea(in: window) else { return finish(true) }
            set(bar, offset: min(1, current + pageFraction(of: area)))
            deadline = Date().addingTimeInterval(timeout)
            usleep(150_000)
        }
        return finish(false)
    }

    /// Opens the collapsed groups already on screen in Finder's focused window, without moving the
    /// view. Cheap enough to run every half second; only steps aside while the user clicks, drags,
    /// types or scrolls, so plain mouse movement does not hold it back.
    @discardableResult
    static func expandVisible() -> Int {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", !userIsBusy,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return 0 }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = element(app, kAXFocusedWindowAttribute) else { return 0 }
        var buttons: [AXUIElement] = []
        collect(window, depth: 0, into: &buttons)
        // Finder repeats the top group's button on its floating header, so pressing every collapsed
        // button at once would open that group and close it again. One button per pass, preferring
        // the one inside the group; the next pass sees the updated titles.
        let collapsed = buttons.filter { isCollapsed(title: title(of: $0)) && (value(of: $0, kAXEnabledAttribute) as Bool?) != false }
        let inGroup = collapsed.filter { parentRole(of: $0) != kAXScrollAreaRole }
        guard let button = (inGroup.isEmpty ? collapsed : inGroup).max(by: { top(of: $0) < top(of: $1) }), !userIsBusy,
              AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return 0 }
        return 1
    }
    private static func parentRole(of element: AXUIElement) -> String? {
        guard let parent = self.element(element, kAXParentAttribute) else { return nil }
        return value(of: parent, kAXRoleAttribute)
    }
    /// Whether the focused icon view is actually grouped: grouped sections are lists named after
    /// their group ("Folders", "Images"…), an ungrouped view has one unnamed list. nil when it
    /// cannot tell (no icon view, or an empty folder).
    static func iconViewIsGrouped() -> Bool? {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        // Only folder windows: on the desktop the same shortcut toggles Stacks.
        guard let window = element(app, kAXFocusedWindowAttribute),
              (value(of: window, kAXIdentifierAttribute) as String?) == "FinderWindow",
              let iconView = findIconView(in: window, depth: 0),
              let sections = (value(iconView, kAXChildrenAttribute) as? [AXUIElement])?.filter({ (value(of: $0, kAXRoleAttribute) as String?) == kAXListRole }),
              !sections.isEmpty else { return nil }
        return sections.contains { !((value(of: $0, kAXDescriptionAttribute) as String?) ?? "").isEmpty }
    }
    /// Finder's "Group By" items carry ⌃⌘ + digit as their key equivalent in every language, so the
    /// digit identifies the item without reading localized titles.
    static func shortcutDigit(for grouping: Grouping) -> String? {
        switch grouping {
        case .name: return "1"
        case .kind: return "2"
        case .opened: return "3"
        case .added: return "4"
        case .modified: return "5"
        case .size: return "6"
        case .tags: return "7"
        case .created, .none: return nil
        }
    }
    /// Groups the focused icon view at once when it is not grouped yet, by pressing Finder's own
    /// menu items through accessibility: no keystrokes are sent, the menu is never opened, and it
    /// takes a few milliseconds where the menu-driven apply takes seconds. Returns true only when
    /// the view went from ungrouped to grouped, so the caller knows it started with no groups.
    static func groupNow(_ grouping: Grouping) -> Bool {
        let diagnostics = CommandLine.arguments.contains("--diagnostics")
        guard let digit = shortcutDigit(for: grouping), !userIsBusy,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              iconViewIsGrouped() == false else { return false }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // An ungrouped view has no "Group By" submenu: "Use Groups" (⌃⌘0) comes first.
        guard pressMenuItem(app, key: "0") else {
            if diagnostics { print("group: Use Groups item not found") }
            return false
        }
        for _ in 0..<10 {
            usleep(80_000)
            if iconViewIsGrouped() == true {
                if !pressMenuItem(app, key: digit), diagnostics { print("group: Group By item not found") }
                return true
            }
        }
        if diagnostics { print("group: view still ungrouped") }
        return false
    }
    /// Presses the enabled item of Finder's View menu whose key equivalent is ⌃⌘ + `key`.
    private static func pressMenuItem(_ app: AXUIElement, key: String) -> Bool {
        guard let bar = element(app, kAXMenuBarAttribute),
              let titles = value(bar, kAXChildrenAttribute) as? [AXUIElement] else { return false }
        // The View menu is the one holding "as Icons" (⌘1).
        for title in titles {
            guard let menu = (value(title, kAXChildrenAttribute) as? [AXUIElement])?.first,
                  let items = value(menu, kAXChildrenAttribute) as? [AXUIElement],
                  items.contains(where: { shortcut(of: $0).map { $0 == ("1", 0) } ?? false }) else { continue }
            func search(_ items: [AXUIElement], depth: Int) -> AXUIElement? {
                for item in items {
                    if let found = shortcut(of: item), found == (key, 4), (value(of: item, kAXEnabledAttribute) as Bool?) != false { return item }
                    if depth < 1, let submenu = (value(item, kAXChildrenAttribute) as? [AXUIElement])?.first,
                       let children = value(submenu, kAXChildrenAttribute) as? [AXUIElement],
                       let found = search(children, depth: depth + 1) { return found }
                }
                return nil
            }
            guard let item = search(items, depth: 0) else { return false }
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }
        return false
    }
    private static func shortcut(of item: AXUIElement) -> (String, Int)? {
        guard let char: String = value(of: item, "AXMenuItemCmdChar"),
              let modifiers = (value(item, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue else { return nil }
        return (char, modifiers)
    }
    private static func findIconView(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if (value(of: element, kAXIdentifierAttribute) as String?) == "IconView" { return element }
        guard depth < 5, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children where (value(of: child, kAXRoleAttribute) as String?) != kAXOutlineRole {
            if let found = findIconView(in: child, depth: depth + 1) { return found }
        }
        return nil
    }
    /// Steps aside only while a button is held, or within a moment of typing, scrolling or dragging.
    /// A finished click (opening a folder) does not delay grouping.
    private static var userIsBusy: Bool {
        NSEvent.pressedMouseButtons != 0 || [CGEventType.keyDown, .scrollWheel, .leftMouseDragged, .rightMouseDown].contains {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < 0.25
        }
    }

    /// The folder Finder is showing in its focused window, as far as accessibility tells: the
    /// window and its title. Cheap enough to read every tenth of a second.
    struct FocusedFolder: Equatable {
        let window: AXUIElement
        let title: String
        static func == (a: Self, b: Self) -> Bool { a.title == b.title && CFEqual(a.window, b.window) }
    }
    static func focusedFolder() -> FocusedFolder? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        return FocusedFolder(window: window, title: value(of: window, kAXTitleAttribute) ?? "")
    }

    /// The scroll area holding Finder's group list.
    private static func groupScrollArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if (value(of: element, kAXRoleAttribute) as String?) == kAXScrollAreaRole,
           let children = value(element, kAXChildrenAttribute) as? [AXUIElement],
           children.contains(where: { (value(of: $0, kAXRoleAttribute) as String?) == kAXListRole }) { return element }
        guard depth < 8, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children { if let found = groupScrollArea(in: child, depth: depth + 1) { return found } }
        return nil
    }
    /// Most of one screen, as a fraction of the scrollable range, so no group header is skipped.
    private static func pageFraction(of area: AXUIElement) -> Double {
        let list = (value(area, kAXChildrenAttribute) as? [AXUIElement])?.first { (value(of: $0, kAXRoleAttribute) as String?) == kAXListRole }
        guard let list, let visible = size(of: area)?.height, let content = size(of: list)?.height, content > visible else { return 1 }
        return max(0.05, Double(visible * 0.8 / (content - visible)))
    }
    private static func offset(of bar: AXUIElement) -> Double? { (value(bar, kAXValueAttribute) as? NSNumber)?.doubleValue }
    private static func set(_ bar: AXUIElement, offset: Double) {
        AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: offset))
    }
    private static func size(of element: AXUIElement) -> CGSize? {
        guard let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(raw as! AXValue, .cgSize, &size)
        return size
    }

    private static func top(of element: AXUIElement) -> CGFloat {
        guard let raw = value(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return 0 }
        var point = CGPoint.zero
        AXValueGetValue(raw as! AXValue, .cgPoint, &point)
        return point.y
    }

    private static func collect(_ element: AXUIElement, depth: Int, into buttons: inout [AXUIElement]) {
        if (value(of: element, kAXIdentifierAttribute) as String?) == identifier { buttons.append(element); return }
        // File icons (groups named after the file) and the sidebar never hold group headers.
        let role: String? = value(of: element, kAXRoleAttribute)
        if role == kAXOutlineRole { return }
        if role == kAXGroupRole, let name: String = value(of: element, kAXIdentifierAttribute), !name.isEmpty, !name.hasPrefix("_NS") { return }
        guard depth < 12, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children { collect(child, depth: depth + 1, into: &buttons) }
    }
    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(element, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private static func value<T>(of element: AXUIElement, _ attribute: String) -> T? { value(element, attribute) as? T }
    private static func title(of element: AXUIElement) -> String { value(of: element, kAXTitleAttribute) ?? "" }
}
