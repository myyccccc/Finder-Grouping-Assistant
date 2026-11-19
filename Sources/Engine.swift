import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import Carbon

enum FinderScripts {
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    static func list(_ names: [String]) -> String { "{" + names.map(quoted).joined(separator: ", ") + "}" }
    static let guardUI = """
    with timeout of 2 seconds
    tell application "System Events" to tell process "Finder"
        if not frontmost then return {"skip", "s1"}
        if not (exists (first window whose subrole is "AXStandardWindow")) then return {"skip", "s2"}
        if exists (first window whose subrole is "AXSystemFloatingWindow") then return {"skip", "s3"}
        set w to first window whose subrole is "AXStandardWindow"
        if value of attribute "AXMain" of w is not true then return {"skip", "s4"}
        -- Copy progress and Info windows are standard windows too; only a folder window has a View menu to change.
        try
            if value of attribute "AXIdentifier" of w is not "FinderWindow" then return {"skip", "s18"}
        end try
        if (count of sheets of w) > 0 then return {"skip", "s5"}
        repeat with anyWindow in windows
            if (count of sheets of anyWindow) > 0 then return {"skip", "s6"}
            try
                if value of attribute "AXIdentifier" of anyWindow is "GoToWindow" then return {"skip", "s7"}
            end try
        end repeat
        repeat with dw in (windows whose subrole is "AXDialog")
            if value of attribute "AXModal" of dw is true then return {"skip", "s8"}
        end repeat
        try
            set f to value of attribute "AXFocusedUIElement"
            set r to value of attribute "AXRole" of f
            if r is in {"AXTextField", "AXTextArea", "AXMenu", "AXMenuItem", "AXComboBox"} then return {"skip", "s9"}
        end try
    end tell
    end timeout
    """
    static let query = guardUI + """

    with timeout of 3 seconds
        tell application "Finder"
            if (count of Finder windows) is 0 then return {"skip", "s10"}
            set w to front Finder window
            set v to current view of w as text
            set s to 0
            if v is "icon view" then
                try
                    set s to icon size of icon view options of w
                end try
            end if
            return {URL of target of w, id of w as text, v, s as text}
        end tell
    end timeout
    """
    /// Switches Finder's front window back to icon view; only the window and folder that were checked.
    static func showView(_ style: String, url: String, windowID: String) -> String {
        """
        with timeout of 3 seconds
            tell application "Finder"
                if (count of Finder windows) is 0 then return {"skip"}
                set w to front Finder window
                if (id of w as text) is not \(quoted(windowID)) then return {"skip"}
                if (URL of target of w) is not \(quoted(url)) then return {"skip"}
                set current view of w to \(style)
            end tell
        end timeout
        return {"ok"}
        """
    }
    /// Sets the icon size of one icon-view window, or of every open icon-view window. Windows are
    /// taken by index: Finder cannot read the view of a window reached through `repeat with w in`.
    static func iconSize(_ size: Int, windowID: String?) -> String {
        let skip = windowID.map { "if (id of w as text) is not \(quoted($0)) then set w to missing value\n" } ?? ""
        return """
        with timeout of 3 seconds
            tell application "Finder"
                set n to count of Finder windows
                repeat with i from 1 to n
                    set w to Finder window i
                    \(skip)if w is not missing value then
                        try
                            if current view of w is icon view then set icon size of icon view options of w to \(size)
                        end try
                    end if
                end repeat
            end tell
        end timeout
        return {"ok"}
        """
    }
    static let automationCheck = """
    with timeout of 3 seconds
        tell application "Finder" to get name
        tell application "System Events" to get name of process "Finder"
    end timeout
    """
    static let activate = """
    with timeout of 3 seconds
        tell application "Finder" to activate
    end timeout
    """
    static func apply(url: String, windowID: String, groups: [String], sorts: [String], hide: Bool) -> String {
        guardUI + """

        with timeout of 4 seconds
            tell application "Finder"
                if (count of Finder windows) is 0 then return {"skip", "s11"}
                if (URL of target of front Finder window) is not \(quoted(url)) then return {"skip", "s12"}
                if (id of front Finder window as text) is not \(quoted(windowID)) then return {"skip", "s13"}
            end tell
            \(guardUI)
            set oldGroup to ""
            set oldSort to ""
            tell application "System Events" to tell process "Finder"
                set viewMenuItem to my findViewMenuItem()
                if viewMenuItem is missing value then error "Finder 当前视图没有可用的分组菜单" number -2700
                set viewMenu to missing value
                try
                click viewMenuItem
                delay 0.12
                set viewMenu to menu 1 of viewMenuItem
                set resolvedMenus to my findMenus(viewMenu)
                set groupMenu to item 1 of resolvedMenus
                set sortMenu to item 2 of resolvedMenus
                if sortMenu is missing value then error "Finder 当前视图没有可用的排序菜单" number -2700
                set oldSort to my markedMenuName(sortMenu)
                if oldSort is "" then error "Finder 当前视图没有可用的排序菜单" number -2700
                set wantsNoGroups to item 1 of \(list(groups)) is in \(list(Grouping.none.menuNames))
                if groupMenu is missing value then
                    set oldGroup to "None"
                    if not wantsNoGroups then
                        set useGroupsItem to missing value
                        repeat with mi in menu items of viewMenu
                            if name of mi is in \(list(FinderMenuNames.useGroups)) then set useGroupsItem to contents of mi
                        end repeat
                        if useGroupsItem is missing value then error "Finder 当前视图没有可用的分组菜单" number -2700
                        if not frontmost then
                            my cancelViewMenu(viewMenu)
                            return {"skip", "s14"}
                        end if
                        click useGroupsItem
                        my cancelViewMenu(viewMenu)
                        delay 0.25
                        set viewMenuItem to my findViewMenuItem()
                        click viewMenuItem
                delay 0.12
                        set viewMenu to menu 1 of viewMenuItem
                        set resolvedMenus to my findMenus(viewMenu)
                        set groupMenu to item 1 of resolvedMenus
                        set sortMenu to item 2 of resolvedMenus
                        if groupMenu is missing value then error "Finder 当前视图没有可用的分组菜单" number -2700
                    end if
                else
                    set oldGroup to my markedMenuName(groupMenu)
                    if oldGroup is "" then error "Finder 当前视图没有可用的分组菜单" number -2700
                end if
                set groupChanged to oldGroup is not in \(list(groups))
                set sortChanged to oldSort is not in \(list(sorts))
                if groupChanged then
                    set groupItem to missing value
                    repeat with mi in menu items of groupMenu
                        if name of mi is in \(list(groups)) then set groupItem to contents of mi
                    end repeat
                    if groupItem is missing value then error "此系统语言暂未支持该分组选项" number -2700
                    if not frontmost then
                        my cancelViewMenu(viewMenu)
                        return {"skip", "s15"}
                    end if
                    click groupItem
                    my cancelViewMenu(viewMenu)
                    delay 0.25
                end if
                if sortChanged then
                    if groupChanged then
                        set viewMenuItem to my findViewMenuItem()
                        if viewMenuItem is missing value then error "Finder 当前视图没有可用的分组菜单" number -2700
                        click viewMenuItem
                delay 0.12
                        set viewMenu to menu 1 of viewMenuItem
                        set resolvedMenus to my findMenus(viewMenu)
                        set sortMenu to item 2 of resolvedMenus
                    end if
                    if sortMenu is missing value then error "Finder 当前视图没有可用的排序菜单" number -2700
                    set sortItem to missing value
                    repeat with mi in menu items of sortMenu
                        if name of mi is in \(list(sorts)) then set sortItem to contents of mi
                    end repeat
                    if sortItem is missing value then error "此系统语言暂未支持该排序选项" number -2700
                    if not frontmost then
                        my cancelViewMenu(viewMenu)
                        return {"skip", "s16"}
                    end if
                    click sortItem
                end if
                my cancelViewMenu(viewMenu)
                on error errorMessage number errorNumber
                    my cancelViewMenu(viewMenu)
                    return {"error", oldGroup, oldSort, errorMessage, errorNumber}
                end try
            end tell
            \(hide ? guardUI + "\ntell application \"Finder\"\nif (URL of target of front Finder window) is not " + quoted(url) + " then return {\"skip\"}\nif (id of front Finder window as text) is not " + quoted(windowID) + " then return {\"skip\"}\nend tell\n" + hiddenScript : "")
            if not groupChanged and not sortChanged and \(hide ? "false" : "true") then return {"unchanged", oldGroup, oldSort}
            return {"ok", oldGroup, oldSort}
        end timeout
        """ + menuDiscovery
    }
    static var menuDiscovery: String {
        """

        on cancelViewMenu(ownedMenu)
            with timeout of 1 second
                try
                    tell application "System Events" to tell process "Finder"
                        if ownedMenu is missing value then
                            set parentItem to my findViewMenuItem()
                            if parentItem is missing value then return
                            set ownedMenu to menu 1 of parentItem
                        end if
                        perform action "AXCancel" of ownedMenu
                    end tell
                end try
            end timeout
        end cancelViewMenu

        on markedMenuName(nativeMenu)
            tell application "System Events" to tell process "Finder"
                repeat with mi in menu items of nativeMenu
                    try
                        set markValue to value of attribute "AXMenuItemMarkChar" of mi
                        if markValue is not missing value and markValue is not "" then return name of mi
                    end try
                end repeat
            end tell
            return ""
        end markedMenuName

        on findViewMenuItem()
            tell application "System Events" to tell process "Finder"
                repeat with parentItem in menu bar items of menu bar 1
                    if name of parentItem is in \(list(FinderMenuNames.view)) then return contents of parentItem
                end repeat
            end tell
            return missing value
        end findViewMenuItem

        on findMenus(viewMenu)
            set groupMenu to missing value
            set sortMenu to missing value
            set groupIndex to 0
            tell application "System Events" to tell process "Finder"
                set candidates to menu items of viewMenu
                repeat with parentItem in candidates
                    if name of parentItem is in \(list(FinderMenuNames.group)) then set groupMenu to menu 1 of parentItem
                    if name of parentItem is in \(list(FinderMenuNames.sort)) then set sortMenu to menu 1 of parentItem
                end repeat
                if sortMenu is not missing value then return {groupMenu, sortMenu}
                repeat with i from 1 to count of candidates
                    try
                        set candidateMenu to menu 1 of item i of candidates
                        repeat with childItem in menu items of candidateMenu
                            if name of childItem is in \(list(Grouping.none.menuNames)) then
                                set groupMenu to candidateMenu
                                set groupIndex to i
                            end if
                            try
                                set shortcutChar to value of attribute "AXMenuItemCmdChar" of childItem
                                set shortcutMods to value of attribute "AXMenuItemCmdModifiers" of childItem
                                if shortcutChar is "2" and shortcutMods is 4 then
                                    set groupMenu to candidateMenu
                                    set groupIndex to i
                                end if
                                if shortcutChar is "1" and shortcutMods is 6 then set sortMenu to candidateMenu
                            end try
                        end repeat
                    end try
                end repeat
                if sortMenu is missing value and groupIndex > 0 then
                    repeat with i from (groupIndex + 1) to count of candidates
                        try
                            set candidateMenu to menu 1 of item i of candidates
                            repeat with childItem in menu items of candidateMenu
                                if name of childItem is in \(list(Grouping.name.menuNames)) then
                                    set sortMenu to candidateMenu
                                    exit repeat
                                end if
                            end repeat
                            if sortMenu is not missing value then exit repeat
                        end try
                    end repeat
                end if
            end tell
            return {groupMenu, sortMenu}
        end findMenus
        """
    }
    static let hiddenScript = """
    tell application "System Events" to tell process "Finder"
        if not frontmost then return {"skip", "s17"}
        key code 47 using {command down, shift down}
    end tell
    """
    static let keepHidden = guardUI + """

    with timeout of 3 seconds
        \(hiddenScript)
        return {"ok"}
    end timeout
    """
}

enum FinderHiddenFileProbe {
    static func isHiddenName(_ name: String) -> Bool { name.hasPrefix(".") && name != "." && name != ".." }
    static func hasVisibleHiddenFiles(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        guard attribute(app, kAXFrontmostAttribute) as? Bool == true,
              let window = attribute(app, kAXMainWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        var pending = [window as! AXUIElement]
        var visited = Set<CFHashCode>()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        var inspected = 0
        while let element = pending.popLast(), inspected < 120, ProcessInfo.processInfo.systemUptime < deadline {
            guard visited.insert(CFHash(element)).inserted else { continue }
            inspected += 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            // Sidebar, toolbar and controls cannot be file items in the folder content.
            if [kAXToolbarRole, kAXMenuRole, kAXScrollBarRole].contains(role) { continue }
            if role == kAXOutlineRole {
                let identifier = (attribute(element, kAXIdentifierAttribute) as? String ?? "").lowercased()
                let description = (attribute(element, kAXDescriptionAttribute) as? String ?? "").lowercased()
                if identifier.contains("sidebar") || description == "sidebar" { continue }
            }
            if role == kAXImageRole || role == kAXStaticTextRole || role == kAXTextFieldRole {
                for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                    if let name = attribute(element, key) as? String, isHiddenName(name) { return true }
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(max(0, 120 - inspected - pending.count)).reversed())
            }
        }
        return false
    }
}

struct ScriptFailure: Error {
    let code: Int
    let message: String
}

enum ScriptRunner {
    // Accessed only on the serial Apple-event queue. Polling scripts are compiled once.
    private static var reusableScripts: [String: NSAppleScript] = [:]
    static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptFailure> {
        let reusable = source == FinderScripts.query || source == FinderScripts.automationCheck || source == FinderScripts.activate || source == FinderScripts.keepHidden
        guard let script = reusableScripts[source] ?? NSAppleScript(source: source) else { return .failure(ScriptFailure(code: -1, message: L.t("无法创建 Finder 操作"))) }
        if reusable { reusableScripts[source] = script }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            let phase = source == FinderScripts.query ? "query" : source == FinderScripts.automationCheck ? "permissions" : source == FinderScripts.activate ? "activate" : "apply"
            NSLog("FinderGrouping %@ error: %@", phase, error.description)
            return .failure(ScriptFailure(code: error[NSAppleScript.errorNumber] as? Int ?? -1,
                                          message: error[NSAppleScript.errorMessage] as? String ?? L.t("Finder 操作未完成")))
        }
        return .success(result)
    }
}

// Read only the focused window's identity and document, with a short AX timeout.
// This avoids asking Finder / System Events for a full UI guard on every timer tick.
enum FinderWindowProbe {
    /// Clicks, drags, typing and scrolling hold automation back for a second. Plain mouse movement
    /// does not: the menus are driven through accessibility, not the pointer, and a mouse that
    /// never quite rests would otherwise keep every folder ungrouped.
    static var userIsInteracting: Bool {
        NSEvent.pressedMouseButtons != 0 || [CGEventType.keyDown, .keyUp, .flagsChanged, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < 1.0
        }
    }
    enum Snapshot { case noWindow, unavailable, document(String) }
    static func snapshot(pid: pid_t) -> Snapshot {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.01)
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue)
        if result == .noValue { return .noWindow }
        guard result == .success, let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return .unavailable }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var document: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &document) == .success,
              let document = document as? String, !document.isEmpty else { return .unavailable }
        guard let view = viewIdentifier(in: window) else { return .unavailable }
        return .document("\(pid):\(CFHash(window)):\(document):\(view)")
    }
    private static func viewIdentifier(in window: AXUIElement) -> String? {
        // Visit only structural containers, never file rows or the sidebar tree.
        var pending: [(AXUIElement, Int)] = [(window, 0)]
        var inspected = 0
        while let (element, depth) = pending.popLast(), inspected < 20 {
            inspected += 1
            var identifier: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success,
               let name = identifier as? String, ["IconView", "ListView", "ColumnView", "GalleryView"].contains(name) { return name }
            guard depth < 3 else { continue }
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                  let name = role as? String,
                  [kAXWindowRole, kAXSplitGroupRole, kAXScrollAreaRole, kAXGroupRole].contains(name) else { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let elements = children as? [AXUIElement] {
                pending.append(contentsOf: elements.prefix(8).reversed().map { ($0, depth + 1) })
            }
        }
        return nil
    }
}

final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            L.language = preferences.language
            if oldValue.language != preferences.language {
                AppDelegate.shared?.updateMenu()
            }
            PersistenceWriter.save(preferences, to: Storage.preferencesURL) { [weak self] error in
                self?.message = L.f("设置保存失败：%@", error.localizedDescription)
            }
            if oldValue.rules != preferences.rules || oldValue.grouping != preferences.grouping || oldValue.sorting != preferences.sorting || oldValue.internalEnabled != preferences.internalEnabled || oldValue.externalEnabled != preferences.externalEnabled || oldValue.hideOnNavigation != preferences.hideOnNavigation {
                lastAppliedKey = nil
                ruleRevision &+= 1
                polling.succeeded()
                AppDelegate.shared?.ruleDidChange()
            }
            if oldValue.engineEnabled != preferences.engineEnabled { ruleRevision &+= 1 }
            if oldValue.hideOnNavigation != preferences.hideOnNavigation { hiddenRepair = FinderHiddenRepairState() }
        }
    }
    @Published var feedbackDraft = ""
    @Published var feedbackIncludesSystem = true
    @Published var activities: [ActivityEntry]
    @Published var volumes: [MountedVolume] = []
    @Published var accessibilityGranted = false
    @Published var automationGranted = false
    @Published var permissionsChecked = false
    @Published var permissionChecking = false
    @Published var legacyRunning = false
    @Published var legacyChecked = 0
    @Published var currentPath: String?
    @Published var currentSource = L.t("等待打开 Finder 文件夹")
    @Published var message: String?
    @Published var selectedPage: Page = .overview
    @Published var overviewHeight: Double = Page.overview.height
    @Published var ruleEditor: LocationRule?
    @Published var showSetup = false {
        didSet {
            guard showSetup != oldValue else { return }
            permissionTimer?.invalidate(); permissionTimer = nil
            if showSetup {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    self?.refreshEnvironment(includeVolumes: false, queueIfBusy: false)
                }
            }
        }
    }
    @Published var busy = false
    private var layouts = FinderLayoutArchive()
    private var timer: Timer?
    private var permissionTimer: Timer?
    private var activationRequested = false
    private var activationSerial: UInt64 = 0
    private var permissionRefreshPending = false
    private var explicitAutomationRequest = false
    private var shuttingDown = false
    private let scriptQueue = DispatchQueue(label: "FinderGroupingAssistant.apple-events")
    private let environmentQueue = DispatchQueue(label: "FinderGroupingAssistant.environment", qos: .utility)
    private let volumeQueue = DispatchQueue(label: "FinderGroupingAssistant.volumes", qos: .utility)
    private let bookmarkQueue = DispatchQueue(label: "FinderGroupingAssistant.bookmarks", qos: .utility)
    private var environmentRefreshInFlight = false
    private var volumeRefreshInFlight = false
    private var volumeRefreshPending = false
    private var finderTaskInFlight = false
    private var activationInFlight = false
    private var permissionCheckInFlight = false
    private let permissionReader: () -> FinderPermissionSnapshot
    private let automationVerifier: () -> Result<NSAppleEventDescriptor, ScriptFailure>
    private var legacyReady = false
    private var ruleRevision: UInt64 = 0
    private var polling = FinderPollingState()
    private var navigationGate = FinderNavigationGate()
    private var hiddenRepair = FinderHiddenRepairState()
    private var lastAppliedKey: String?
    private var failureKey: String?
    // Finder collapses icon-view groups on every visit and again whenever it refreshes the view,
    // so groups are kept open: a full pass once per visit, then on-screen groups on every check.
    private var expandedVisitKey: String?
    private var expandableWindow: (signature: String, visit: String, cacheKey: String, grouping: Grouping)?
    // Finder can drop a folder's grouping later (often on external drives), so a remembered layout
    // is checked against what the window shows and applied again when the groups are gone.
    private var lastRegroup = Date.distantPast
    private var expansionInFlight = false
    private var expandTimer: Timer?
    private var lastIconSwitch: (key: String, date: Date) = ("", .distantPast)
    // Checks run every 0.1 s for 2 s after Finder shows a different folder, then every 0.5 s.
    private var expandTicks = 0
    private var lastFocusedFolder: FinderGroupExpander.FocusedFolder?
    private var focusedFolderChangedAt = Date.distantPast
    // When the instant shortcut last grouped a folder; the menu pass that follows records that
    // folder's original layout as ungrouped.
    private var instantGroupedAt = Date.distantPast
    private let expandQueue = DispatchQueue(label: "FinderGroupingAssistant.expand", qos: .userInitiated)
    private var lastFailureDate = Date.distantPast
    /// Failures in a row for `failureKey`. Most are momentary (a window still opening, Finder's
    /// View menu not built yet), so the first retries come quickly; only a lasting failure waits.
    private var failureStreak = 0
    static let retryDelays: [TimeInterval] = [1, 3, 30]
    private var retryDelay: TimeInterval { Self.retryDelays[min(max(failureStreak, 1), Self.retryDelays.count) - 1] }
    private var lastPermissionRefresh = Date.distantPast
    private var lastVolumeRefresh = Date.distantPast
    private var bookmarks: [URL] = []
    let legacyBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FinderKindGrouping")
    let legacyLabels = ["local.finder-kind-grouping", "local.finder-kind-grouping.live"]

    var active: Bool { preferences.engineEnabled || legacyRunning }
    var isRunning: Bool { preferences.engineEnabled && accessibilityGranted && automationGranted }
    var todayCount: Int { activities.filter { Calendar.current.isDateInToday($0.date) && $0.path != nil && $0.success }.count }
    var todayFailureCount: Int { activities.filter { Calendar.current.isDateInToday($0.date) && !$0.success }.count }
    var statusTitle: String {
        if legacyRunning { return L.t("旧版服务运行中") }
        if preferences.engineEnabled && !accessibilityGranted { return L.t("等待辅助功能权限") }
        if preferences.engineEnabled && !automationGranted { return L.t("等待自动化权限") }
        return preferences.engineEnabled ? L.t("自动分组已开启") : L.t("准备好，让 Finder 更有序")
    }
    var statusDetail: String {
        if legacyRunning { return L.t("已读取原有服务。启用新版后，路径与设备规则将接管分组。") }
        return preferences.engineEnabled ? L.t("打开文件夹时，自动应用最适合它的规则。") : L.t("设定一次，每次打开文件夹都井然有序。")
    }
    var preferredColorScheme: ColorScheme? {
        preferences.appearance == "light" ? .light : preferences.appearance == "dark" ? .dark : nil
    }

    static func readPermissions() -> FinderPermissionSnapshot {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow" {
            return FinderPermissionSnapshot(accessibility: false, automation: .unknown, available: false)
        }
        let granted = AXIsProcessTrusted()
        func statuses() -> [Int32] { ["com.apple.finder", "com.apple.systemevents"].map { identifier in
            let target = NSAppleEventDescriptor(bundleIdentifier: identifier)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        } }
        var values = statuses()
        if granted && values.last == -600 {
            // Start the Apple background agent without sending an Apple Event or prompting.
            // This makes a passive TCC query reliable while grouping is paused too.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.promptsUserIfNeeded = false
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"), configuration: config) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 2)
            values = statuses()
        }
        return FinderPermissionSnapshot(accessibility: granted, automation: AutomationPermissionState.resolve(values))
    }
    init(preferences override: Preferences? = nil,
         permissionReader: @escaping () -> FinderPermissionSnapshot = AppModel.readPermissions,
         automationVerifier: @escaping () -> Result<NSAppleEventDescriptor, ScriptFailure> = { ScriptRunner.run(FinderScripts.automationCheck) },
         prepareEnvironment: Bool = true) {
        self.permissionReader = permissionReader
        self.automationVerifier = automationVerifier
        var prefs = override ?? Storage.read(Preferences.self, from: Storage.preferencesURL) ?? Preferences()
        // 1.2.7 removed scope switches and per-folder rules from the UI; hidden settings must not linger.
        if override == nil { prefs.internalEnabled = true; prefs.externalEnabled = true; prefs.rules = [] }
        preferences = prefs
        L.language = prefs.language
        activities = Storage.read([ActivityEntry].self, from: Storage.activityURL) ?? []
        layouts = Storage.read(FinderLayoutArchive.self, from: Storage.layoutsURL) ?? FinderLayoutArchive()
        // Older activity entries contain the earliest observed native values.
        for entry in activities.reversed() {
            if entry.success, let path = entry.path, let group = entry.previousGroup, let sort = entry.previousSort {
                layouts.remember(OriginalFinderLayout(path: path, view: "*", volumeID: nil, group: group, sort: sort), fingerprint: nil)
            }
        }
        saveLayouts()
        if !prepareEnvironment { legacyReady = true }
        refreshEnvironment(includeVolumes: prepareEnvironment)
        guard prepareEnvironment else { return }
        refreshLegacy()
        openBookmarks()
        configureTimer()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in self?.lastAppliedKey = nil; self?.navigationGate = FinderNavigationGate(); self?.refreshEnvironment() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshEnvironment() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshEnvironment(includeVolumes: false) }
        for notification in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in self?.refreshEnvironment(includeVolumes: false) }
        }
    }
    private func configureTimer() {
        timer?.invalidate()
        let interval = 1.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = min(0.5, interval * 0.1)
        expandTimer?.invalidate()
        expandTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.expandVisibleGroups() }
        expandTimer?.tolerance = 0.02
    }
    /// Groups stay open in every icon-view window: whatever Finder collapses on screen is reopened
    /// within a tenth of a second of opening a folder (half a second afterwards), without moving the view.
    private func expandVisibleGroups() {
        guard preferences.engineEnabled, !shuttingDown, accessibilityGranted, !expansionInFlight, !busy,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        expandTicks += 1
        let recentlyChanged = Date().timeIntervalSince(focusedFolderChangedAt) < 2
        expansionInFlight = true
        // With no folder or device rules every location shares the global rule, so a folder can be
        // grouped the moment it opens, ahead of the slower Apple-event query (which still follows,
        // checks the sort order and records the original layout). Finder does not expose the
        // window's path to accessibility, so other setups wait for that query.
        let instantGrouping: Grouping? = preferences.rules.isEmpty && preferences.internalEnabled && preferences.externalEnabled && preferences.grouping != .none ? preferences.grouping : nil
        let previous = lastFocusedFolder, slowTick = expandTicks % 5 == 0
        expandQueue.async { [weak self] in
            let folder = FinderGroupExpander.focusedFolder()
            let changed = folder != nil && folder != previous
            guard changed || recentlyChanged || slowTick else {
                DispatchQueue.main.async { self?.expansionInFlight = false }
                return
            }
            let grouped = instantGrouping.map { FinderGroupExpander.groupNow($0) } ?? false
            let count = FinderGroupExpander.expandVisible()
            DispatchQueue.main.async {
                guard let self else { return }
                self.expansionInFlight = false
                if changed { self.lastFocusedFolder = folder; self.focusedFolderChangedAt = Date() }
                if grouped {
                    self.instantGroupedAt = Date()
                    self.scheduleFinderCheck()
                }
                if CommandLine.arguments.contains("--diagnostics") {
                    if grouped { print("grouped on open") }
                    if count > 0 { print("expand visible", count) }
                }
            }
        }
    }
    func refreshEnvironment(includeVolumes: Bool = true, queueIfBusy: Bool = true) {
        guard !shuttingDown else { return }
        if includeVolumes || Date().timeIntervalSince(lastVolumeRefresh) > 60 { refreshVolumes() }
        guard !environmentRefreshInFlight else {
            if queueIfBusy { permissionRefreshPending = true }
            return
        }
        environmentRefreshInFlight = true
        permissionChecking = true
        lastPermissionRefresh = Date()
        environmentQueue.async { [weak self] in
            let snapshot = self?.permissionReader()
            guard let snapshot else { return }
            let granted = snapshot.accessibility
            let automation = snapshot.automation
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.environmentRefreshInFlight = false
                guard snapshot.available else {
                    self.permissionChecking = false
                    return
                }
                self.permissionsChecked = true
                if self.accessibilityGranted != granted { self.accessibilityGranted = granted }
                switch automation {
                case .allowed: if !self.automationGranted { self.automationGranted = true }
                case .denied: if self.automationGranted { self.automationGranted = false }
                case .unknown:
                    // System Events exits when idle. procNotFound is not a permission denial.
                    // Unknown includes an idle System Events process, not a denied permission.
                    break
                }
                if self.permissionRefreshPending {
                    self.permissionRefreshPending = false
                    self.refreshEnvironment(includeVolumes: false)
                    return
                }
                if granted && self.explicitAutomationRequest && automation == .denied {
                    self.explicitAutomationRequest = false
                    self.verifyAutomation()
                } else {
                    if automation == .allowed { self.explicitAutomationRequest = false }
                    self.permissionChecking = self.permissionCheckInFlight
                    self.finishPermissionFlow()
                }
            }
        }
    }
    private func refreshVolumes() {
        guard !volumeRefreshInFlight else { volumeRefreshPending = true; return }
        volumeRefreshInFlight = true; lastVolumeRefresh = Date()
        volumeQueue.async { [weak self] in
            let discovered = MountedVolume.discover()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.volumeRefreshInFlight = false
                if self.volumes != discovered { self.volumes = discovered }
                if self.volumeRefreshPending { self.volumeRefreshPending = false; self.refreshVolumes() }
            }
        }
    }
    private func verifyAutomation() {
        guard !shuttingDown, !permissionCheckInFlight, !busy else {
            permissionChecking = environmentRefreshInFlight || permissionCheckInFlight
            return
        }
        permissionCheckInFlight = true
        permissionChecking = true
        scriptQueue.async { [weak self] in
            guard let self else { return }
            let result = self.automationVerifier()
            let trusted = self.permissionReader().accessibility
            DispatchQueue.main.async {
                self.permissionCheckInFlight = false
                self.permissionChecking = self.environmentRefreshInFlight
                self.accessibilityGranted = trusted
                guard !self.shuttingDown else { return }
                switch result {
                case .success:
                    self.automationGranted = true
                    self.message = nil
                    self.finishPermissionFlow()
                case .failure(let failure):
                    if failure.code == -1743 || failure.code == -1744 {
                        self.automationGranted = false
                        self.explicitAutomationRequest = false
                        self.handle(failure)
                    } else { self.message = L.t("暂时无法确认权限，请重试。") }
                    self.activationRequested = false
                    self.showSetup = true
                }
            }
        }
    }
    func refreshLegacy() {
        environmentQueue.async { [weak self] in
            guard let self = self else { return }
            let running = self.legacyLabels.contains { label in self.command("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).0 == 0 }
            var checked = 0
            if let raw = try? Data(contentsOf: self.legacyBase.appendingPathComponent("status.json")), let status = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] { checked = status["checked_folders"] as? Int ?? 0 }
            DispatchQueue.main.async {
                self.legacyReady = true
                if self.legacyRunning != running { self.legacyRunning = running }
                if self.legacyChecked != checked { self.legacyChecked = checked }
                self.finishPermissionFlow()
            }
        }
    }
    func openBookmarks() {
        let rules = preferences.rules
        bookmarkQueue.async { [weak self] in
        guard let self = self else { return }
        for url in self.bookmarks { url.stopAccessingSecurityScopedResource() }
        self.bookmarks.removeAll()
        for rule in rules {
            guard let bookmark = rule.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if url.startAccessingSecurityScopedResource() { self.bookmarks.append(url) }
            }
        }
        }
    }
    func start() {
        guard !shuttingDown, !busy, !finderTaskInFlight else { return }
        activationSerial &+= 1
        activationRequested = true
        explicitAutomationRequest = true
        message = nil
        refreshEnvironment(includeVolumes: false)
    }
    func showPermissionSetup() {
        message = nil
        showSetup = true
        refreshEnvironment(includeVolumes: false)
    }
    func cancelPermissionSetup() {
        activationRequested = false
        explicitAutomationRequest = false
        activationSerial &+= 1
        if !isRunning { preferences.engineEnabled = false }
        preferences.hasCompletedSetup = true
        showSetup = false
    }
    private func finishPermissionFlow() {
        guard !shuttingDown, permissionsChecked, !permissionChecking, !busy else { return }
        guard accessibilityGranted, automationGranted else {
            if !showSetup && (activationRequested || preferences.engineEnabled || !preferences.hasCompletedSetup) { showSetup = true }
            return
        }
        guard legacyReady else { return }
        if activationRequested || !preferences.hasCompletedSetup {
            let serial = activationSerial
            if legacyRunning {
                busy = true
                migrateLegacy { [weak self] succeeded in
                    guard let self else { return }
                    self.busy = false
                    if succeeded && !self.shuttingDown && serial == self.activationSerial {
                        self.enableEngine(takingOverLegacy: true)
                    }
                }
            } else { enableEngine(takingOverLegacy: false) }
        } else if showSetup { showSetup = false }
    }
    private func enableEngine(takingOverLegacy: Bool) {
        activationRequested = false
        explicitAutomationRequest = false
        preferences.hasCompletedSetup = true
        preferences.engineEnabled = true
        if takingOverLegacy { setLoginItem(true) }
        lastAppliedKey = nil; failureKey = nil; failureStreak = 0; polling.succeeded()
        showSetup = false
        log(L.t("自动分组已开启"), detail: L.t("全局、路径和设备规则已生效"))
    }
    func prepareForQuit(completion: @escaping () -> Void) {
        shuttingDown = true
        timer?.invalidate()
        expandTimer?.invalidate()
        permissionTimer?.invalidate()
        activationRequested = false
        activationSerial &+= 1
        // Let any in-flight native menu operation finish and persist its observed layout.
        scriptQueue.async { DispatchQueue.main.async(execute: completion) }
    }
    func pause() {
        activationRequested = false
        explicitAutomationRequest = false
        activationSerial &+= 1
        preferences.hasCompletedSetup = true
        preferences.engineEnabled = false
        lastAppliedKey = nil
        log(L.t("自动分组已暂停"), detail: L.t("Finder 保留当前显示状态；可随时继续"))
    }
    /// While Finder is too busy to answer, requests wait until this time.
    private var finderBusyUntil = Date.distantPast
    static let finderBusyPause: TimeInterval = 10
    func tick() {
        // Pausing stops every automated Finder operation, including hidden-file repair.
        guard preferences.engineEnabled, !shuttingDown, Date() >= finderBusyUntil else { return }
        if CommandLine.arguments.contains("--diagnostics") {
            print("tick", legacyReady, legacyRunning, accessibilityGranted, automationGranted, busy, finderTaskInFlight, NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil", FinderWindowProbe.userIsInteracting)
        }
        if Date().timeIntervalSince(lastPermissionRefresh) > 60 { refreshEnvironment(includeVolumes: false) }
        guard preferences.engineEnabled, legacyReady, !legacyRunning, accessibilityGranted, automationGranted, !busy, !finderTaskInFlight, polling.canQuery(at: Date()),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        guard !FinderWindowProbe.userIsInteracting,
              let finder = NSWorkspace.shared.frontmostApplication else { return }
        finderTaskInFlight = true
        let revision = ruleRevision
        let gate = navigationGate
        scriptQueue.async { [weak self] in
            let signature: String?
            switch FinderWindowProbe.snapshot(pid: finder.processIdentifier) {
            case .noWindow:
                DispatchQueue.main.async { self?.finderTaskInFlight = false }
                return
            case .unavailable: signature = nil
            case .document(let value): signature = value
            }
            guard gate.shouldQuery(signature: signature, revision: revision, at: Date()) else {
                DispatchQueue.main.async {
                    self?.finderTaskInFlight = false
                    if self?.repairHiddenFilesIfNeeded() != true { self?.keepGroupsExpanded(signature: signature) }
                }
                return
            }
            let raw = ScriptRunner.run(FinderScripts.query)
            if CommandLine.arguments.contains("--diagnostics"), case .success(let value) = raw, value.atIndex(1)?.stringValue == "skip" {
                print("query skipped", value.atIndex(2)?.stringValue ?? "")
            }
            let result = raw.map { FinderLocation.inspect($0) }
            DispatchQueue.main.async { self?.processQuery(result, revision: revision, signature: signature) }
        }
    }
    // Only the enabled engine checks the hidden-file preference; no UI tree scans.
    private func repairHiddenFilesIfNeeded() -> Bool {
        guard preferences.engineEnabled, !shuttingDown, preferences.hideOnNavigation, legacyReady, !legacyRunning,
              accessibilityGranted, automationGranted, !busy, !finderTaskInFlight,
              hiddenRepair.isDue(at: Date()), !FinderWindowProbe.userIsInteracting,
              let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else { return false }
        hiddenRepair.didCheck(at: Date())
        finderTaskInFlight = true
        scriptQueue.async { [weak self] in
            var result: Result<NSAppleEventDescriptor, ScriptFailure>?
            // Read one preference instead of traversing Finder's accessibility tree.
            if FinderVisibilityPreference.showsHiddenFiles, !FinderWindowProbe.userIsInteracting {
                result = ScriptRunner.run(FinderScripts.keepHidden)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.finderTaskInFlight = false
                if case .failure(let error) = result {
                    self.hiddenRepair.failed(at: Date())
                    if error.code == -1743 || error.code == -25211 { self.handle(error) }
                }
            }
        }
        return true
    }
    private func processQuery(_ result: Result<FinderLocation?, ScriptFailure>, revision: UInt64, signature: String?) {
        finderTaskInFlight = false
        if CommandLine.arguments.contains("--diagnostics") { print("query", result) }
        guard preferences.engineEnabled, !shuttingDown, revision == ruleRevision else { return }
        switch result {
        case .failure(let error):
            if error.code == -1712 {
                // Finder is busy (a large copy, a slow volume): leave it alone for a while, then
                // carry on by itself. Pausing for good here left grouping off for days.
                finderBusyUntil = Date().addingTimeInterval(Self.finderBusyPause)
                message = L.t("Finder 操作未完成")
                return
            }
            polling.failed(at: Date())
            handle(error)
        case .success(let location):
            polling.succeeded()
            guard let location = location, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
            let path = location.path
            if currentPath != path { currentPath = path }
            let rule = RuleResolver.resolve(path: path, volumeID: location.volumeID,
                                            isExternal: location.isExternal, preferences: preferences)
            let source = rule.excluded ? L.t("此位置已排除") : rule.source
            if currentSource != source { currentSource = source }
            // Folders always open as icons when asked; a list, column or gallery window is switched back.
            if !rule.excluded, let style = preferences.viewStyle.scriptName, !location.view.isEmpty, !preferences.viewStyle.matches(location.view) {
                showView(style, location)
                return
            }
            if !rule.excluded, liveIconSize == nil, let size = preferences.iconSize, location.view == "icon view", let current = location.iconSize, current != size {
                setIconSize(size, windowID: location.windowID)
            }
            let key = location.urlString + ":" + location.windowID + ":" + location.view + ":" + rule.grouping.rawValue + ":" + rule.sorting.rawValue + ":" + String(preferences.hideOnNavigation)
            let visit = location.urlString + ":" + location.windowID + ":" + location.view
            if expandedVisitKey != visit { expandedVisitKey = nil }
            if let signature, !rule.excluded, rule.grouping != .none, location.view == "icon view" {
                expandableWindow = (signature, visit, FinderLayoutArchive.key(path: path, view: location.view, volumeID: location.volumeID), rule.grouping)
            } else { expandableWindow = nil }
            let cacheKey = FinderLayoutArchive.key(path: path, view: location.view, volumeID: location.volumeID)
            let fingerprint = FinderLayoutArchive.fingerprint(group: rule.grouping, sort: rule.sorting, hide: preferences.hideOnNavigation)
            let knownLayout = (!location.isExternal || location.volumeID != nil) && layouts.confirmed[cacheKey] == fingerprint
            if rule.excluded || lastAppliedKey == key || knownLayout {
                navigationGate.record(signature: signature, revision: revision, at: Date())
                if !rule.excluded { expandGroupsIfNeeded(urlString: location.urlString, windowID: location.windowID, view: location.view, grouping: rule.grouping) }
                if !rule.excluded, rule.grouping != .none, location.view == "icon view" { regroupIfLost(cacheKey: cacheKey, grouping: rule.grouping) }
                return
            }
            if failureKey == key && Date().timeIntervalSince(lastFailureDate) < retryDelay { return }
            apply(urlString: location.urlString, path: path, windowID: location.windowID, view: location.view, volumeID: location.volumeID, rule: rule, key: key, signature: signature)
        }
    }
    private func apply(urlString: String, path: String, windowID: String, view: String, volumeID: String?, rule: EffectiveRule, key: String, signature: String?) {
        busy = true
        let revision = ruleRevision
        let hideRequested = preferences.hideOnNavigation
        scriptQueue.async { [weak self] in
            guard !FinderWindowProbe.userIsInteracting else {
                DispatchQueue.main.async { self?.busy = false }
                return
            }
            let shouldHide = hideRequested && FinderVisibilityPreference.showsHiddenFiles
            let appliedGrouping = FinderViewSupport.grouping(rule.grouping, in: view)
            // Show the groups right away; the menu pass below then checks the sort order and records
            // the original layout. A folder grouped here started with no groups.
            let groupedByShortcut = view == "icon view" && FinderGroupExpander.groupNow(appliedGrouping)
            if groupedByShortcut, CommandLine.arguments.contains("--diagnostics") { print("grouped by shortcut", path) }
            let source = FinderScripts.apply(url: urlString, windowID: windowID, groups: appliedGrouping.menuNames, sorts: rule.sorting.menuNames, hide: shouldHide)
            let result = ScriptRunner.run(source)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                // Preserve the observed baseline even if the user pauses during an operation.
                if case .success(let value) = result, ["ok", "unchanged", "error"].contains(value.atIndex(1)?.stringValue ?? "") {
                    let original = OriginalFinderLayout(path: path, view: view, volumeID: volumeID,
                        group: groupedByShortcut || Date().timeIntervalSince(self.instantGroupedAt) < 10 ? "None" : value.atIndex(2)?.stringValue ?? "", sort: value.atIndex(3)?.stringValue ?? "")
                    self.layouts.remember(original, fingerprint: nil)
                    self.saveLayouts()
                }
                guard self.preferences.engineEnabled, revision == self.ruleRevision else { return }
                switch result {
                case .failure(let error):
                    if CommandLine.arguments.contains("--diagnostics") { print("apply failed", error) }
                    self.noteFailure(key); self.handle(error)
                case .success(let value):
                    let status = value.atIndex(1)?.stringValue
                    if CommandLine.arguments.contains("--diagnostics") { print("apply", value) }
                    if status == "error" {
                        self.noteFailure(key)
                        self.handle(ScriptFailure(code: Int(value.atIndex(5)?.int32Value ?? -1), message: value.atIndex(4)?.stringValue ?? L.t("Finder 操作未完成")))
                        return
                    }
                    guard status == "ok" || status == "unchanged" else { return }
                    self.navigationGate.record(signature: signature, revision: revision, at: Date())
                    self.lastAppliedKey = key
                    let original = OriginalFinderLayout(path: path, view: view, volumeID: volumeID,
                        group: groupedByShortcut || Date().timeIntervalSince(self.instantGroupedAt) < 10 ? "None" : value.atIndex(2)?.stringValue ?? "", sort: value.atIndex(3)?.stringValue ?? "")
                    self.layouts.remember(original, fingerprint: FinderLayoutArchive.fingerprint(group: rule.grouping, sort: rule.sorting, hide: hideRequested))
                    self.instantGroupedAt = .distantPast
                    self.saveLayouts()
                    self.failureKey = nil; self.failureStreak = 0
                    self.message = appliedGrouping != rule.grouping ? L.t("此 Finder 视图仅支持排序") : nil
                    self.expandGroupsIfNeeded(urlString: urlString, windowID: windowID, view: view, grouping: appliedGrouping)
                    guard status == "ok" else { return }
                    self.log(!FinderViewSupport.supportsGrouping(in: view) ? L.f("已应用%@排序", rule.sorting.title) : L.f("已应用%@分组", rule.grouping.title), detail: L.f("%@ · 按%@排序", rule.source, rule.sorting.title), path: path,
                             previousGroup: value.atIndex(2)?.stringValue, previousSort: value.atIndex(3)?.stringValue, windowID: windowID)
                }
            }
        }
    }
    private func showView(_ style: String, _ location: FinderLocation) {
        let key = location.windowID + ":" + location.urlString
        guard !busy, !(lastIconSwitch.key == key && Date().timeIntervalSince(lastIconSwitch.date) < 1) else { return }
        lastIconSwitch = (key, Date())
        busy = true
        scriptQueue.async { [weak self] in
            let result = ScriptRunner.run(FinderScripts.showView(style, url: location.urlString, windowID: location.windowID))
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if CommandLine.arguments.contains("--diagnostics") { print("view", style, location.view, "->", result) }
                self.scheduleFinderCheck()
            }
        }
    }
    /// The size the slider is being dragged through; the engine does not correct windows meanwhile.
    private(set) var liveIconSize: Int?
    private var liveIconSizeInFlight = false
    /// Follows the slider while it moves: Finder gets the newest size as soon as the previous
    /// change has landed, so the icons resize live without queuing up stale sizes.
    func previewIconSize(_ size: Int) {
        liveIconSize = size
        guard !liveIconSizeInFlight else { return }
        liveIconSizeInFlight = true
        scriptQueue.async { [weak self] in
            _ = ScriptRunner.run(FinderScripts.iconSize(size, windowID: nil))
            DispatchQueue.main.async {
                guard let self else { return }
                self.liveIconSizeInFlight = false
                if let latest = self.liveIconSize, latest != size { self.previewIconSize(latest) }
            }
        }
    }
    /// The slider was let go: keep the size and make sure every window ends on it.
    func commitIconSize(_ size: Int) {
        liveIconSize = nil
        preferences.iconSize = size
        setIconSize(size, windowID: nil)
    }
    /// Applies the chosen icon size; nil window means every open icon-view window (slider moved).
    func setIconSize(_ size: Int, windowID: String?) {
        scriptQueue.async {
            let result = ScriptRunner.run(FinderScripts.iconSize(size, windowID: windowID))
            if CommandLine.arguments.contains("--diagnostics") { print("icon size", size, windowID ?? "all", result) }
        }
    }
    private func expandGroupsIfNeeded(urlString: String, windowID: String, view: String, grouping: Grouping) {
        let visit = urlString + ":" + windowID + ":" + view
        guard view == "icon view", grouping != .none, expandedVisitKey != visit, !expansionInFlight else { return }
        expansionInFlight = true
        scriptQueue.async { [weak self] in
            let result = FinderGroupExpander.expandAll(scrolls: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.expansionInFlight = false
                // An interrupted pass is retried on the next check.
                if result.finished { self.expandedVisitKey = visit }
                if CommandLine.arguments.contains("--diagnostics") { print("expand", visit, result) }
            }
        }
    }
    /// Called while the same folder stays open: finishes an interrupted first pass, then reopens
    /// any on-screen group Finder has collapsed again, without moving the view.
    private func keepGroupsExpanded(signature: String?) {
        guard let signature, let window = expandableWindow, window.signature == signature,
              !busy, !finderTaskInFlight, !expansionInFlight else { return }
        let fullPass = expandedVisitKey != window.visit
        expansionInFlight = true
        scriptQueue.async { [weak self] in
            let grouped = FinderGroupExpander.iconViewIsGrouped()
            let result = grouped == false ? (expanded: 0, finished: false) : FinderGroupExpander.expandAll(timeout: fullPass ? 1.0 : 0.2, scrolls: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.expansionInFlight = false
                if grouped == false { self.regroupIfLost(cacheKey: window.cacheKey, grouping: window.grouping); return }
                if fullPass, result.finished { self.expandedVisitKey = window.visit }
                if CommandLine.arguments.contains("--diagnostics") { print("keep expanded", window.visit, fullPass, result) }
            }
        }
    }
    private func regroupIfLost(cacheKey: String, grouping: Grouping) {
        guard !expansionInFlight else { return }
        expansionInFlight = true
        let grouping = grouping
        scriptQueue.async { [weak self] in
            let grouped = FinderGroupExpander.iconViewIsGrouped()
            let restored = grouped == false && FinderGroupExpander.groupNow(grouping)
            DispatchQueue.main.async {
                guard let self else { return }
                self.expansionInFlight = false
                if CommandLine.arguments.contains("--diagnostics"), grouped == false { print("groups lost; shortcut restored:", restored) }
                if grouped == false, !restored { self.forgetLayout(cacheKey: cacheKey) }
            }
        }
    }
    /// Drops the remembered layout so the next check applies the rule again. Limited to once every
    /// 10 seconds, so a view Finder is still redrawing cannot cause a loop of menu operations.
    private func forgetLayout(cacheKey: String) {
        guard Date().timeIntervalSince(lastRegroup) > 10 else { return }
        lastRegroup = Date()
        if CommandLine.arguments.contains("--diagnostics") { print("groups lost, applying again", cacheKey) }
        layouts.confirmed[cacheKey] = nil
        lastAppliedKey = nil
        navigationGate = FinderNavigationGate()
        scheduleFinderCheck()
    }
    func applyNow() {
        guard !shuttingDown else { return }
        guard preferences.engineEnabled else { start(); return }
        lastAppliedKey = nil; failureKey = nil
        navigationGate = FinderNavigationGate()
        polling.succeeded()
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: finder) }
            if finder.activate(options: [.activateIgnoringOtherApps]) { scheduleFinderCheck() }
            else { activateFinderForAction() }
        }
    }
    func openLocation(_ path: String) {
        if !NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true)) { message = L.t("Finder 操作未完成") }
        var activated = false
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: finder) }
            activated = finder.activate(options: [.activateIgnoringOtherApps])
        }
        if activated { scheduleFinderCheck() }
        else if automationGranted { activateFinderForAction() }
    }
    private func scheduleFinderCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.tick() }
    }
    private func activateFinderForAction() {
        guard !activationInFlight else { return }
        activationInFlight = true
        scriptQueue.async { [weak self] in
            let result = ScriptRunner.run(FinderScripts.activate)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activationInFlight = false
                if case .failure(let error) = result { self.handle(error); return }
                self.scheduleFinderCheck()
            }
        }
    }
    private func saveLayouts() {
        PersistenceWriter.save(layouts, to: Storage.layoutsURL) { [weak self] error in
            self?.message = L.f("设置保存失败：%@", error.localizedDescription)
        }
    }
    func restoreCurrentFolder() {
        guard !busy, !finderTaskInFlight else { return }
        pause()
        AppDelegate.shared?.closeForFinderAction()
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return }
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: finder) }
        finder.activate(options: [.activateIgnoringOtherApps])
        busy = true
        scriptQueue.async { [weak self] in
            let query = ScriptRunner.run(FinderScripts.query).map { FinderLocation.inspect($0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if case .failure(let error) = query {
                    self.handle(error)
                    AppDelegate.shared?.showWindow(); return
                }
                guard case .success(let location?) = query else {
                    self.message = L.t("请先在 Finder 中打开要还原的文件夹。")
                    AppDelegate.shared?.showWindow(); return
                }
                guard let original = self.layouts.original(path: location.path, view: location.view, volumeID: location.volumeID) else {
                    self.message = L.t("这个文件夹尚无可还原的原始排列记录。")
                    AppDelegate.shared?.showWindow(); return
                }
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = L.t("还原当前文件夹排列？")
                alert.informativeText = L.t("恢复助手首次记录前的分组和排序，并暂停自动分组。") + "\n\n" + readablePath(location.path)
                alert.addButton(withTitle: L.t("还原")); alert.addButton(withTitle: L.t("取消"))
                guard alert.runModal() == .alertFirstButtonReturn else { AppDelegate.shared?.showWindow(); return }
                finder.activate(options: [.activateIgnoringOtherApps])
                self.busy = true
                self.scriptQueue.asyncAfter(deadline: .now() + 2.1) { [weak self] in
                    guard let self, !self.shuttingDown else { return }
                    let result: Result<NSAppleEventDescriptor, ScriptFailure>
                    let current = ScriptRunner.run(FinderScripts.query).map { FinderLocation.inspect($0) }
                    if !FinderWindowProbe.userIsInteracting, case .success(let live?) = current,
                       live.path == location.path, live.volumeID == location.volumeID {
                        let groups = Grouping.allCases.first { $0.menuNames.contains(original.group) }?.menuNames ?? [original.group]
                        let sorts = Grouping.allCases.first { $0.menuNames.contains(original.sort) }?.menuNames ?? [original.sort]
                        result = ScriptRunner.run(FinderScripts.apply(url: live.urlString, windowID: live.windowID, groups: groups, sorts: sorts, hide: false))
                    } else { result = .success(NSAppleEventDescriptor.list()) }
                    DispatchQueue.main.async {
                        self.busy = false
                        if case .success(let value) = result, ["ok", "unchanged"].contains(value.atIndex(1)?.stringValue ?? "") {
                            self.layouts.forgetConfirmation(path: location.path); self.saveLayouts()
                            self.message = L.t("已还原当前文件夹排列，自动分组已暂停。")
                        } else { self.message = L.t("还原未完成，请保持原文件夹打开并停止操作后重试。") }
                        AppDelegate.shared?.showWindow()
                    }
                }
            }
        }
    }
    func undo(_ entry: ActivityEntry) {
        guard !busy else { return }
        guard let path = entry.path, let group = entry.previousGroup, !group.isEmpty,
              let sort = entry.previousSort, !sort.isEmpty, let window = entry.windowID else { return }
        busy = true
        // Undo is guarded by both target URL and window identity to avoid changing another folder.
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: finder) }
            finder.activate(options: [.activateIgnoringOtherApps])
        }
        preferences.engineEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.busy = true
            self.scriptQueue.async {
                let result = ScriptRunner.run(FinderScripts.apply(url: URL(fileURLWithPath: path, isDirectory: true).absoluteString, windowID: window, groups: [group], sorts: [sort], hide: false))
                DispatchQueue.main.async {
                    self.busy = false
                    switch result {
                    case .failure(let error): self.handle(error)
                    case .success(let value):
                        if ["ok", "unchanged"].contains(value.atIndex(1)?.stringValue ?? "") {
                            self.log(L.t("已恢复上次显示设置"), detail: L.t("自动分组已暂停，避免立即覆盖恢复结果"), path: path)
                        } else { self.message = L.t("请先回到记录中的原 Finder 窗口，再恢复设置。自动分组已暂停。") }
                    }
                }
            }
        }
    }
    private func noteFailure(_ key: String) {
        failureStreak = failureKey == key ? failureStreak + 1 : 1
        failureKey = key
    }
    private func handle(_ error: ScriptFailure) {
        let text: String
        if error.code == -1743 { automationGranted = false; text = L.t("请在系统设置 → 隐私与安全性 → 自动化中允许 Finder 和 System Events。") }
        else if error.code == -1719 || error.code == -25211 { text = L.t("请为 Finder 分组助手开启辅助功能权限。") }
        else if error.code == -1712 { text = L.t("Finder 操作未完成") }
        else { text = L.t(error.message) }
        message = text
        if failureStreak >= Self.retryDelays.count, Date().timeIntervalSince(lastFailureDate) > 30 {
            log(L.t("分组未完成"), detail: text, success: false)
        }
        lastFailureDate = Date()
    }
    func log(_ title: String, detail: String, path: String? = nil, success: Bool = true, previousGroup: String? = nil, previousSort: String? = nil, windowID: String? = nil) {
        activities.insert(ActivityEntry(title: title, detail: detail, path: path, success: success, previousGroup: previousGroup, previousSort: previousSort, windowID: windowID), at: 0)
        if activities.count > 500 { activities = Array(activities.prefix(500)) }
        PersistenceWriter.save(activities, to: Storage.activityURL) { [weak self] error in
            self?.message = L.f("运行记录保存失败：%@", error.localizedDescription)
        }
    }
    func chooseFolder(excluded: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = excluded ? L.t("选择保持原有 Finder 显示设置的文件夹") : L.t("选择要单独设定规则的文件夹")
        panel.prompt = L.t("选择文件夹")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let existing = preferences.rules.first(where: { $0.scope == .folder && RuleResolver.normalized($0.path) == RuleResolver.normalized(url.path) }) {
            ruleEditor = existing; return
        }
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        ruleEditor = LocationRule(name: url.lastPathComponent, path: url.path, excluded: excluded, grouping: preferences.grouping, sorting: preferences.sorting, bookmark: bookmark)
    }
    func editDevice(_ volume: MountedVolume) {
        if let rule = preferences.rules.first(where: { RuleResolver.matchesDevice($0, uuid: volume.uuid, path: volume.path) }) {
            ruleEditor = rule
        } else {
            ruleEditor = LocationRule(name: volume.name, path: volume.path, volumeID: volume.uuid, scope: .device, grouping: preferences.grouping, sorting: preferences.sorting)
        }
    }
    func saveRule(_ rule: LocationRule) {
        var rule = rule
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.name.isEmpty { rule.name = URL(fileURLWithPath: rule.path).lastPathComponent }
        if let index = preferences.rules.firstIndex(where: { $0.id == rule.id }) { preferences.rules[index] = rule }
        else { preferences.rules.append(rule) }
        openBookmarks()
        log(L.t("规则已保存"), detail: "\(rule.name) · \(rule.excluded ? L.t("保持原有设置") : rule.grouping.title)")
        ruleEditor = nil
    }
    func deleteRule(_ id: UUID) {
        preferences.rules.removeAll { $0.id == id }
        openBookmarks()
    }
    @Published var preGroupingAvailable = PreGrouping.canRestore
    /// Records the grouping rules for the folders in the home folder ahead of time. Finder quits for
    /// the few seconds of writing and opens again.
    func preGroupFolders(roots: [URL]? = nil, confirm: Bool = true) {
        guard !busy, !shuttingDown else { return }
        if confirm {
            let alert = NSAlert(); alert.messageText = L.t("预先整理文件夹？")
            alert.informativeText = L.t("助手会把个人文件夹中的子文件夹提前设为当前的分组和图标视图，之后打开时 Finder 直接显示分组。整理期间 Finder 会退出几秒再自动打开。改动前会备份，可随时还原。外接设备不受影响。")
            alert.addButton(withTitle: L.t("开始整理")); alert.addButton(withTitle: L.t("取消"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        busy = true
        message = L.t("正在预先整理文件夹…")
        let preferences = preferences, iconSize = preferences.iconSize
        let roots = roots ?? [FileManager.default.homeDirectoryForCurrentUser]
        scriptQueue.async { [weak self] in
            let parents = PreGrouping.parents(of: roots)
            var outcome: PreGrouping.Outcome?
            let quit = PreGrouping.quitFinder()
            if quit { outcome = PreGrouping.apply(parents: parents, preferences: preferences, iconSize: iconSize) }
            PreGrouping.launchFinder()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.preGroupingAvailable = PreGrouping.canRestore
                self.lastAppliedKey = nil
                guard let outcome else { self.message = L.t("Finder 未能退出，请完成正在进行的拷贝等操作后重试。"); return }
                self.message = outcome.folders == 0 ? L.t("没有需要整理的文件夹。") : L.f("已预先整理 %@ 个文件夹", L.number(outcome.folders))
                self.log(L.t("预先整理文件夹"), detail: L.f("已预先整理 %@ 个文件夹", L.number(outcome.folders)))
                if CommandLine.arguments.contains("--diagnostics") { print("pregroup", parents.count, outcome.folders, outcome.files, outcome.skipped) }
            }
        }
    }
    func restorePreGrouping(confirm: Bool = true) {
        guard !busy, !shuttingDown, PreGrouping.canRestore else { return }
        if confirm {
            let alert = NSAlert(); alert.messageText = L.t("还原预先整理？")
            alert.informativeText = L.t("将恢复整理前的 Finder 显示设置。Finder 会退出几秒再自动打开。")
            alert.addButton(withTitle: L.t("开始还原")); alert.addButton(withTitle: L.t("取消"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        busy = true
        scriptQueue.async { [weak self] in
            var restored: Int?
            if PreGrouping.quitFinder() { restored = PreGrouping.restore() }
            PreGrouping.launchFinder()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.preGroupingAvailable = PreGrouping.canRestore
                guard let restored else { self.message = L.t("Finder 未能退出，请完成正在进行的拷贝等操作后重试。"); return }
                self.message = L.f("已还原 %@ 个位置的显示设置", L.number(restored))
            }
        }
    }
    func exportPreferences() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = L.t("Finder分组规则.json"); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try Storage.save(PreferenceImport.portable(preferences), to: url) }
            catch { message = L.f("导出失败：%@", error.localizedDescription) }
        }
    }
    func importPreferences() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var prefs = Storage.read(Preferences.self, from: url), PreferenceImport.validate(prefs) else { message = L.t("此文件不是有效的 Finder 分组规则。"); return }
        let alert = NSAlert(); alert.messageText = L.t("导入并替换当前规则？"); alert.informativeText = L.f("将导入 %@ 条位置规则。当前设置会先自动备份。", L.number(prefs.rules.count)); alert.addButton(withTitle: L.t("导入规则")); alert.addButton(withTitle: L.t("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try Storage.save(preferences, to: Storage.directory.appendingPathComponent("before-import.json")) }
        catch { message = L.t("无法备份现有规则，导入已取消。"); return }
        prefs = PreferenceImport.portable(prefs)
        prefs.hasCompletedSetup = preferences.hasCompletedSetup
        prefs.engineEnabled = preferences.engineEnabled; preferences = prefs; openBookmarks()
        log(L.t("已导入规则"), detail: L.t("现有设置已备份为 before-import.json"))
    }
    func exportActivity() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = L.t("Finder运行记录.json"); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try Storage.save(activities, to: url) }
            catch { message = L.f("导出失败：%@", error.localizedDescription) }
        }
    }
    func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func openAutomation() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
    func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        } catch { message = L.f("登录启动设置未完成：%@", error.localizedDescription) }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var loginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    var canRestoreLegacy: Bool { FileManager.default.fileExists(atPath: Storage.directory.appendingPathComponent("legacy-backup/migration.json").path) }
    private func migrateLegacy(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = L.t("由新版接管自动分组？")
        alert.informativeText = L.t("新版会暂停旧版的两个后台服务，并备份其登录配置。原有文件和显示备份会保留。以后可在设置中恢复旧版。")
        alert.addButton(withTitle: L.t("启用新版")); alert.addButton(withTitle: L.t("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { completion(false); return }
        busy = true
        environmentQueue.async { [self] in
        let backup = Storage.directory.appendingPathComponent("legacy-backup")
        let agents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        do {
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            var saved: [String] = []
            for label in legacyLabels {
                let source = agents.appendingPathComponent(label + ".plist")
                if FileManager.default.fileExists(atPath: source.path) {
                    let target = backup.appendingPathComponent(label + ".plist")
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
                    saved.append(label)
                }
            }
            try Storage.save(saved, to: backup.appendingPathComponent("migration.json"))
            for label in saved {
                let stopped = command("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
                // launchd may retain the service while its process finishes shutting down.
                let deadline = Date().addingTimeInterval(8)
                while command("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).0 == 0 && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.2)
                }
                if command("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).0 == 0 {
                    throw NSError(domain: "Migration", code: 1, userInfo: [NSLocalizedDescriptionKey: L.t("旧版服务仍在运行") + (stopped.1.isEmpty ? "" : ": " + stopped.1.trimmingCharacters(in: .whitespacesAndNewlines))])
                }
                let source = agents.appendingPathComponent(label + ".plist")
                try FileManager.default.removeItem(at: source)
            }
            DispatchQueue.main.async {
                self.busy = false; self.legacyRunning = false; self.legacyReady = true
                self.log(L.t("已切换到新版"), detail: L.t("旧版启动配置已备份，可从设置恢复"))
                completion(true)
            }
        } catch {
            let failure = error
            DispatchQueue.main.async {
                self.busy = false
                self.restoreLegacy(confirm: false)
                self.message = L.f("迁移未完成，已尝试恢复旧版：%@", failure.localizedDescription)
                completion(false)
            }
        }
        }
    }
    func restoreLegacy(confirm: Bool = true) {
        guard !busy else { return }
        if confirm {
            let alert = NSAlert(); alert.messageText = L.t("恢复旧版后台服务？"); alert.informativeText = L.t("新版自动分组将暂停，旧版恢复按种类分组、按名称排序的行为。新版规则仍会保留。"); alert.addButton(withTitle: L.t("恢复旧版")); alert.addButton(withTitle: L.t("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        preferences.engineEnabled = false
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            do { try SMAppService.mainApp.unregister() }
            catch { message = L.f("新版登录启动未能停用：%@", error.localizedDescription) }
        }
        busy = true
        environmentQueue.async { [self] in
        let backup = Storage.directory.appendingPathComponent("legacy-backup")
        guard let labels = Storage.read([String].self, from: backup.appendingPathComponent("migration.json")) else {
            DispatchQueue.main.async { self.busy = false; self.message = L.t("Finder 操作未完成") }; return
        }
        let agents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        do {
            for label in labels where legacyLabels.contains(label) {
                let source = backup.appendingPathComponent(label + ".plist"), target = agents.appendingPathComponent(label + ".plist")
                if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
                if command("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).0 != 0 {
                    let result = command("/bin/launchctl", ["bootstrap", "gui/\(getuid())", target.path])
                    if result.0 != 0 { throw NSError(domain: "Migration", code: Int(result.0), userInfo: [NSLocalizedDescriptionKey: result.1]) }
                }
            }
            let running = legacyLabels.contains { command("/bin/launchctl", ["print", "gui/\(getuid())/\($0)"]).0 == 0 }
            DispatchQueue.main.async {
                self.busy = false; self.legacyRunning = running; self.legacyReady = true
                self.log(L.t("已恢复旧版服务"), detail: L.t("新版规则已保留"))
            }
        } catch {
            let failure = error
            DispatchQueue.main.async { self.busy = false; self.message = L.f("旧版恢复未完成：%@", failure.localizedDescription) }
        }
        }
    }
    func command(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "") }
        catch { return (-1, error.localizedDescription) }
    }
}
