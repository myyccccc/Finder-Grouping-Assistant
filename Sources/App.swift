import SwiftUI
import AppKit
import Combine
import ApplicationServices
import Carbon

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static weak var shared: AppDelegate?
    var model: AppModel?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var pendingApply: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?

    static func main() {
        if CommandLine.arguments.contains("--self-test") { SelfTests.run(); return }
        if CommandLine.arguments.contains("--permission-flow-test") { PermissionFlowTests.run(); return }
        if CommandLine.arguments.contains("--permission-diagnostics") {
            let statuses = ["com.apple.finder", "com.apple.systemevents"].map {
                AEDeterminePermissionToAutomateTarget(NSAppleEventDescriptor(bundleIdentifier: $0).aeDesc, typeWildCard, typeWildCard, false)
            }
            let data: [String: Any] = ["accessibility": AXIsProcessTrusted(), "automationStatuses": statuses,
                "bundle": Bundle.main.bundleIdentifier ?? "", "appPath": Bundle.main.bundlePath]
            if let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]), let text = String(data: json, encoding: .utf8) { print(text) }
            return
        }
        // Diagnostics are usually redirected to a file; write each line as it happens.
        if CommandLine.arguments.contains("--diagnostics") { setvbuf(stdout, nil, _IOLBF, 0) }
        _ = NSAppleScript(source: "return true")?.compileAndReturnError(nil)
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let model = AppModel()
        self.model = model
        if CommandLine.arguments.contains("--enable") { model.start() }
        // Test hook: pre-group only below the given folder, without asking.
        if let index = CommandLine.arguments.firstIndex(of: "--pregroup-root"), index + 1 < CommandLine.arguments.count {
            let root = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.preGroupFolders(roots: [root], confirm: false) }
        }
        // Start at login by default, once. Turning it off later in Settings is respected.
        if !UserDefaults.standard.bool(forKey: "LoginItemDefaulted.v1") {
            UserDefaults.standard.set(true, forKey: "LoginItemDefaulted.v1")
            if !model.loginEnabled && !model.loginNeedsApproval { model.setLoginItem(true) }
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: RootView().environmentObject(model))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A named item: macOS 27 kept the old unnamed "Item-0" hidden even after it was allowed again.
        statusItem?.autosaveName = "FinderGroupingMenu"
        statusItem?.isVisible = true
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(togglePopover)
        updateMenu()
        if CommandLine.arguments.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                let item = self?.statusItem
                print("status item", item?.isVisible as Any, item?.length as Any, item?.button?.window?.frame as Any,
                      item?.button?.window?.isVisible as Any, item?.button?.window?.occlusionState.contains(.visible) as Any)
            }
        }
        UpdateChecker.shared.start { [weak model] in model?.preferences.updateFrequency ?? .manual }
        model.$overviewHeight.receive(on: RunLoop.main).sink { [weak self] _ in self?.updatePopoverSize() }.store(in: &subscriptions)
        model.$selectedPage.receive(on: RunLoop.main).sink { [weak self] _ in self?.updatePopoverSize() }.store(in: &subscriptions)
        model.$ruleEditor.receive(on: RunLoop.main).sink { [weak self] rule in
            self?.updatePopoverSize()
            if rule != nil { self?.showWindow(resetPage: false) }
        }.store(in: &subscriptions)
        model.$showSetup.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] showing in
            self?.updatePopoverSize()
            if showing { self?.showWindow(resetPage: false) }
        }.store(in: &subscriptions)
        model.$preferences.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateMenu() }.store(in: &subscriptions)
        model.$busy.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateMenu() }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--permission-audit") {
            model.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { self?.writePermissionAudit() }
            }.store(in: &subscriptions)
        }
        // Show the new widget once after migration; subsequent launches stay in the menu bar.
        if !UserDefaults.standard.bool(forKey: "ShownMenuBarWidget.v1") {
            UserDefaults.standard.set(true, forKey: "ShownMenuBarWidget.v1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showWindow() }
        }
        if CommandLine.arguments.contains("--show-widget") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showWindow() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func writePermissionAudit() {
        guard let model else { return }
        let state: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "accessibility": model.accessibilityGranted, "automation": model.automationGranted,
            "engineEnabled": model.preferences.engineEnabled, "setupVisible": model.showSetup,
            "checking": model.permissionChecking, "checked": model.permissionsChecked, "running": model.isRunning]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/finder-permission-audit.json"), options: .atomic)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        pendingApply?.cancel()
        guard let model else { return .terminateNow }
        model.prepareForQuit {
            PersistenceWriter.flush { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return false }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showWindow() }
    }
    func showWindow(resetPage: Bool = true) {
        guard let button = statusItem?.button, let model else { return }
        model.refreshEnvironment(includeVolumes: false)
        if resetPage && !model.showSetup && model.ruleEditor == nil { model.selectedPage = .overview }
        updatePopoverSize()
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        if let window = popover.contentViewController?.view.window {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.makeKey()
        }
    }
    private func updatePopoverSize() {
        guard let model else { return }
        let height = WidgetLayout.height(for: model)
        popover.contentSize = NSSize(width: WidgetLayout.width, height: height)
    }
    func updateMenu() {
        guard let model else { return }
        let image = BrandArtwork.menuBarImage
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = L.t("Finder 分组助手")
        statusItem?.button?.setAccessibilityLabel(L.t("Finder 分组助手"))
        popover.appearance = model.preferences.appearance == "dark" ? NSAppearance(named: .darkAqua) : model.preferences.appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    // Choosing a rule behaves like a native menu selection: close, then update Finder.
    // This keeps the original frontmost-Finder and interaction guards intact.
    func ruleDidChange() {
        pendingApply?.cancel()
        guard popover.isShown, model?.preferences.engineEnabled == true,
              model?.selectedPage == .overview || model?.selectedPage == .rules else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.popover.isShown, let model = self.model, model.preferences.engineEnabled,
                  model.selectedPage == .overview || model.selectedPage == .rules,
                  !model.showSetup, model.ruleEditor == nil else { return }
            self.popover.performClose(nil)
            model.applyNow()
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    // .transient only works when the popover window became key. macOS 14+ may ignore
    // activate(ignoringOtherApps:) for a menu bar app, so clicks elsewhere never closed it.
    func popoverDidShow(_ notification: Notification) {
        removeDismissMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismissFromOutside()
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.popover.isShown, self.model?.ruleEditor == nil else { return event }
            self.popover.performClose(nil)
            return nil
        }
    }
    func popoverDidClose(_ notification: Notification) { removeDismissMonitors() }
    private func dismissFromOutside() {
        // Keep the permission setup open while the user switches to System Settings.
        guard popover.isShown, model?.showSetup != true else { return }
        // A rule chosen just before the outside click still gets applied.
        if let work = pendingApply, !work.isCancelled { pendingApply = nil; work.perform(); work.cancel() }
        if popover.isShown { popover.performClose(nil) }
    }
    private func removeDismissMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        outsideClickMonitor = nil; escapeMonitor = nil
    }
    func closeForFinderAction() { pendingApply?.cancel(); popover.performClose(nil) }
    func quit() { NSApp.terminate(nil) }
}

enum SelfTests {
    static func run() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { print("FAIL: \(name)"); exit(1) }
            count += 1
        }
        do {
            var store = DSStoreFile()
            for i in 0..<400 { store.set("文件夹 \(i)", "GRP0", type: "ustr", payload: DSStoreFile.ustr(i % 2 == 0 ? "Kind" : "Name")) }
            store.set("Alpha", "icvp", type: "blob", payload: DSStoreFile.blob(Data(repeating: 7, count: 600)))
            store.set("Alpha", "GRP0", type: "ustr", payload: DSStoreFile.ustr("Kind"))
            let decoded = try? DSStoreFile(data: store.encoded())
            check(decoded == store && store.records.count == 402, "DS_Store round trip across several pages")
            check(store.records.first?.name == "Alpha" && store.records[0].code == "GRP0" && store.records[1].code == "icvp", "DS_Store keeps Finder's record order")
            check(decoded?.string("文件夹 3", "GRP0") == "Name", "DS_Store reads grouping records")
            check((try? DSStoreFile(data: DSStoreFile().encoded()))?.records.isEmpty == true, "empty DS_Store is valid")
            check((try? DSStoreFile(data: Data("not a store".utf8))) == nil, "foreign file is rejected")
        }
        check(PreGrouping.groupCode(.kind) == "Kind" && PreGrouping.groupCode(.tags) == "Finder Tags" && PreGrouping.groupCode(.none) == nil, "Finder group codes")
        check(PreGrouping.arrangeBy(.modified) == "dateModified", "Finder arrangement codes")
        check(FinderGroupExpander.isCollapsed(title: "Show All (18)"), "collapsed Finder group title has a count")
        check(!FinderGroupExpander.isCollapsed(title: "Show Less"), "expanded Finder group title has no count")
        check(FinderGroupExpander.isCollapsed(title: "全部显示（18）") && FinderGroupExpander.isCollapsed(title: "عرض الكل (١٨)"), "group counts are recognized in any script")
        check(!FinderGroupExpander.isCollapsed(title: "收起"), "localized expanded title is left alone")
        var p = Preferences()
        check(RuleResolver.resolve(path: "/Users/demo/Pictures", volumeID: nil, isExternal: false, preferences: p).source == L.t("全局默认"), "global fallback")
        check(RuleResolver.resolve(path: "/Volumes/SD/DCIM", volumeID: "A", isExternal: true, preferences: p).grouping == .kind, "external inherits global")
        p.externalEnabled = false
        check(RuleResolver.resolve(path: "/Volumes/SD/DCIM", volumeID: "A", isExternal: true, preferences: p).excluded, "external scope disabled")
        p.externalEnabled = true
        let device = LocationRule(name: "SD", path: "/Volumes/SD", volumeID: "A", scope: .device, grouping: .created)
        p.rules = [device]
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM", volumeID: "A", isExternal: true, preferences: p).grouping == .created, "device UUID survives rename")
        check(RuleResolver.resolve(path: "/Volumes/SD/DCIM", volumeID: "B", isExternal: true, preferences: p).source == L.t("全局默认"), "same name different device")
        check(!RuleResolver.matchesDevice(device, uuid: "B", path: "/Volumes/SD"), "editor does not confuse identically named devices")
        check(RuleResolver.matchesDevice(device, uuid: "A", path: "/Volumes/Renamed"), "editor recognizes renamed device")
        let mountOne = MountedVolume(name: "Disk", path: "/Volumes/Disk", uuid: "A", external: true, removable: true, readOnly: true, total: 0, available: 0)
        let mountTwo = MountedVolume(name: "Disk", path: "/Volumes/Disk 1", uuid: "A", external: true, removable: true, readOnly: true, total: 0, available: 0)
        check(mountOne.id != mountTwo.id, "cloned volumes keep distinct SwiftUI row identities")
        let parent = LocationRule(name: "Photos", path: "/Volumes/Renamed/DCIM", grouping: .modified)
        let child = LocationRule(name: "Day 2", path: "/Volumes/Renamed/DCIM/Day2", grouping: .tags)
        p.rules.append(contentsOf: [parent, child])
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM/A", volumeID: "A", isExternal: true, preferences: p).grouping == .modified, "path overrides device")
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM/Day2/A", volumeID: "A", isExternal: true, preferences: p).grouping == .tags, "deepest path wins")
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM-extra", volumeID: "A", isExternal: true, preferences: p).grouping == .created, "component boundary")
        p.rules[1].includeChildren = false
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM/A", volumeID: "A", isExternal: true, preferences: p).grouping == .created, "exact-only folder")
        p.rules[2].excluded = true
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM/Day2", volumeID: "A", isExternal: true, preferences: p).excluded, "excluded path")
        p.rules[2].enabled = false
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM/Day2", volumeID: "A", isExternal: true, preferences: p).grouping == .created, "disabled rule ignored")
        check(RuleResolver.contains("/", "/Users/demo"), "root boundary")
        check(RuleResolver.contains("/tmp/../Users/demo/", "/Users/demo/child"), "path normalization")
        var disabledScopes = p
        disabledScopes.externalEnabled = false
        check(RuleResolver.resolve(path: "/Volumes/Renamed/DCIM", volumeID: "A", isExternal: true, preferences: disabledScopes).excluded, "external scope off disables device overrides")
        disabledScopes.internalEnabled = false
        disabledScopes.rules = [LocationRule(name: "Folder", path: "/Users/demo/Test", grouping: .size)]
        check(RuleResolver.resolve(path: "/Users/demo/Test", volumeID: nil, isExternal: false, preferences: disabledScopes).excluded, "internal scope off disables folder overrides")
        var importFixture = Preferences()
        importFixture.engineEnabled = true
        importFixture.rules = [LocationRule(name: "Quoted", path: "/Users/demo/Folder \"中文\"", bookmark: Data([1,2,3]))]
        check(PreferenceImport.validate(importFixture), "valid spaces quotes and Unicode paths import")
        let portableFixture = PreferenceImport.portable(importFixture)
        check(!portableFixture.engineEnabled && portableFixture.rules.first?.bookmark == nil && importFixture.engineEnabled && importFixture.rules.first?.bookmark != nil, "portable backup removes active state and bookmarks without changing source")
        importFixture.rules.append(importFixture.rules[0])
        check(!PreferenceImport.validate(importFixture), "duplicate rule IDs rejected")
        importFixture.rules.removeLast(); importFixture.rules[0].path = "relative/folder"
        check(!PreferenceImport.validate(importFixture), "relative import path rejected")
        importFixture.rules[0].path = "/Users/demo/line\rbreak"
        check(!PreferenceImport.validate(importFixture), "carriage return import path rejected")
        importFixture = Preferences(); importFixture.appearance = "unknown"
        check(!PreferenceImport.validate(importFixture), "unknown appearance rejected")
        importFixture = Preferences(); importFixture.language = "unknown"
        check(!PreferenceImport.validate(importFixture), "unknown language rejected")
        var polling = FinderPollingState()
        let clock = Date(timeIntervalSince1970: 1000)
        check(polling.canQuery(at: clock), "initial polling allowed")
        for delay: TimeInterval in [4, 8, 16, 30, 30] {
            polling.failed(at: clock)
            check(!polling.canQuery(at: clock.addingTimeInterval(delay - 0.1)) && polling.canQuery(at: clock.addingTimeInterval(delay)), "timeout retry backoff \(delay)")
        }
        polling.succeeded()
        check(polling.failures == 0 && polling.canQuery(at: clock), "explicit retry clears backoff")
        check(AutomationPermissionState.resolve([0, 0]) == .allowed, "automation explicitly allowed")
        check(AutomationPermissionState.resolve([0, -600]) == .unknown, "idle System Events is not permission denial")
        check(AutomationPermissionState.resolve([-1743, -600]) == .denied, "revoked automation takes precedence")
        check(AutomationPermissionState.resolve([0, -1744]) == .denied, "new automation requires consent")
        check(AutomationPermissionState.resolve([0, -1712]) == .unknown, "automation timeout is not permission denial")
        check(FinderHiddenFileProbe.isHiddenName(".DS_Store") && FinderHiddenFileProbe.isHiddenName(".隐藏文件"), "visible dot files recognized")
        check(!FinderHiddenFileProbe.isHiddenName(".") && !FinderHiddenFileProbe.isHiddenName("..") && !FinderHiddenFileProbe.isHiddenName("photo.jpg"), "ordinary names do not toggle Finder hidden state")
        var hiddenRepair = FinderHiddenRepairState()
        let hiddenTime = Date()
        check(hiddenRepair.isDue(at: hiddenTime), "hidden preference takes effect immediately")
        hiddenRepair.didCheck(at: hiddenTime)
        check(!hiddenRepair.isDue(at: hiddenTime.addingTimeInterval(7.9)), "hidden repair does not scan every tick")
        check(hiddenRepair.isDue(at: hiddenTime.addingTimeInterval(8)), "hidden repair checks current folder again")
        hiddenRepair.failed(at: hiddenTime)
        check(!hiddenRepair.isDue(at: hiddenTime.addingTimeInterval(29)), "hidden repair errors back off")
        check(hiddenRepair.isDue(at: hiddenTime.addingTimeInterval(30)), "hidden repair recovers after backoff")
        var gate = FinderNavigationGate()
        let now = Date()
        check(gate.shouldQuery(signature: "window:folder", revision: 1, at: now), "first directory is queried")
        gate.record(signature: "window:folder", revision: 1, at: now)
        check(!gate.shouldQuery(signature: "window:folder", revision: 1, at: now.addingTimeInterval(60)), "unchanged directory does not send repeated Apple events")
        check(gate.shouldQuery(signature: "window:other", revision: 1, at: now), "navigation triggers a query")
        check(gate.shouldQuery(signature: "other-window:folder", revision: 1, at: now), "different Finder window triggers a query")
        gate.record(signature: "window:folder:IconView", revision: 1, at: now)
        check(gate.shouldQuery(signature: "window:folder:ListView", revision: 1, at: now), "view changes in the same directory trigger a query")
        check(!gate.shouldQuery(signature: "window:folder:IconView", revision: 1, at: now.addingTimeInterval(60)), "unchanged view stays idle")
        check(Grouping.allCases.allSatisfy { FinderViewSupport.grouping($0, in: "gallery view") == .none }, "gallery never attempts unavailable grouping")
        check(["flow view", "group view"].allSatisfy { FinderViewSupport.grouping(.kind, in: $0) == .none }, "Finder scripting dictionary gallery aliases are supported")
        check(["icon view", "list view", "column view"].allSatisfy { view in Grouping.allCases.allSatisfy { FinderViewSupport.grouping($0, in: view) == $0 } }, "other Finder views preserve requested grouping")
        check(gate.shouldQuery(signature: "window:folder", revision: 2, at: now), "rule edits take effect in current folder")
        gate.record(signature: nil, revision: 1, at: now)
        check(!gate.shouldQuery(signature: nil, revision: 1, at: now.addingTimeInterval(9)), "unknown AX document has bounded fallback")
        check(gate.shouldQuery(signature: nil, revision: 1, at: now.addingTimeInterval(10)), "unknown AX document remains supported")
        check(SoftwareUpdateFrequency.allCases.count == 3 && Preferences().updateFrequency == .weekly, "software update frequency has daily, weekly and manual choices")
        p.updateFrequency = .manual
        check(FeedbackReport.make(message: "  example feedback  ", includeSystem: false) == "example feedback", "feedback can omit all system metadata")
        check(FeedbackReport.make(message: "example", includeSystem: true).contains("macOS "), "optional feedback includes system version")
        check(!FeedbackReport.make(message: "example", includeSystem: true).contains(FileManager.default.homeDirectoryForCurrentUser.path), "feedback never collects local file paths")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("FinderGroupingTests-" + UUID().uuidString)
        do {
            let target = temp.appendingPathComponent("preferences.json")
            try Storage.save(p, to: target)
            check(Storage.read(Preferences.self, from: target) == p, "settings round trip")
            var archive = FinderLayoutArchive()
            let original = OriginalFinderLayout(path: "/Users/demo/Photos", view: "icon", volumeID: "internal", group: "None", sort: "Name")
            archive.remember(original, fingerprint: "kind:name:true")
            archive.remember(OriginalFinderLayout(path: original.path, view: original.view, volumeID: original.volumeID, group: "Kind", sort: "Size"), fingerprint: "size:size:true")
            check(archive.original(path: original.path, view: original.view, volumeID: original.volumeID) == original, "later rules do not replace original Finder layout")
            let archiveURL = temp.appendingPathComponent("layouts.json")
            try Storage.save(archive, to: archiveURL)
            let reopened = Storage.read(FinderLayoutArchive.self, from: archiveURL)!
            check(reopened.original(path: original.path, view: original.view, volumeID: original.volumeID) == original, "Finder baseline survives application relaunch")
            check(reopened.confirmed == archive.confirmed, "applied-layout cache survives quit")
            check(reopened.original(path: original.path, view: "list", volumeID: original.volumeID) == nil, "restore does not confuse native view modes")
            archive.remember(OriginalFinderLayout(path: original.path, view: "*", volumeID: nil, group: "Kind", sort: "Size"), fingerprint: nil)
            check(archive.original(path: original.path, view: original.view, volumeID: original.volumeID) == original, "exact baseline takes precedence over legacy unknown view")

            archive.remember(OriginalFinderLayout(path: "/Volumes/Card/DCIM", view: "icon", volumeID: "card-A", group: "None", sort: "Name"), fingerprint: "kind:name:true")
            check(archive.original(path: "/Volumes/Card/DCIM", view: "icon", volumeID: "card-B") == nil, "restore does not confuse identically named external devices")
            archive.remember(OriginalFinderLayout(path: "/Volumes/Card/DCIM", view: "*", volumeID: nil, group: "None", sort: "Name"), fingerprint: nil)
            check(archive.original(path: "/Volumes/Card/DCIM", view: "icon", volumeID: "card-B") == nil, "legacy record cannot restore an unidentified external disk")
            archive.forgetConfirmation(path: original.path)
            check(archive.confirmed[FinderLayoutArchive.key(path: original.path, view: original.view, volumeID: original.volumeID)] == nil && archive.confirmed.count == 1, "restoration invalidates only the restored folder cache")
            check(FinderLayoutArchive.fingerprint(group: .kind, sort: .name, hide: true) != FinderLayoutArchive.fingerprint(group: .modified, sort: .name, hide: true), "rule edits invalidate persisted applied layouts")
            check(FinderVisibilityPreference.bool("true") && FinderVisibilityPreference.bool(NSNumber(value: 1)) && !FinderVisibilityPreference.bool(nil) && !FinderVisibilityPreference.bool("false"), "hidden-file preference handles unset, numeric, and textual values")

            check(Storage.read(Preferences.self, from: temp.appendingPathComponent("missing")) == nil, "missing settings handled")
            let asyncTarget = temp.appendingPathComponent("async-settings.json")
            let secondTarget = temp.appendingPathComponent("async-other.json")
            for value in 0..<100 { PersistenceWriter.save(value, to: asyncTarget) { error in print("FAIL: async persistence \(error)"); exit(1) } }
            PersistenceWriter.save("independent", to: secondTarget) { error in print("FAIL: async persistence \(error)"); exit(1) }
            PersistenceWriter.flushForTests()
            check(Storage.read(Int.self, from: asyncTarget) == 99, "coalesced settings keep newest change before quit")
            check(Storage.read(String.self, from: secondTarget) == "independent", "pending saves do not overwrite other files")
            check(FinderLocation.inspect(NSAppleEventDescriptor.list()) == nil, "empty Finder response is ignored")
            try FileManager.default.removeItem(at: temp)
        } catch { print("FAIL: persistence \(error)"); exit(1) }
        for source in [FinderScripts.query, FinderScripts.automationCheck, FinderScripts.activate, FinderScripts.keepHidden] + Grouping.allCases.map({ FinderScripts.apply(url: "file:///tmp/Folder%20Name/", windowID: "1", groups: $0.menuNames, sorts: Sorting.name.menuNames, hide: true) }) {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.compileAndReturnError(&error) == true else { print("FAIL: AppleScript compile \(String(describing: error))"); exit(1) }
            count += 1
        }
        check(FinderScripts.quoted("a\"b\\c") == "\"a\\\"b\\\\c\"", "AppleScript escaping")
        check(FinderScripts.guardUI.hasPrefix("with timeout of 2 seconds"), "UI guard has a bounded timeout")
        check(!FinderScripts.hiddenScript.contains("entire contents"), "hidden-file action never enumerates the complete accessibility tree")
        check(!FinderScripts.apply(url: "file:///tmp/", windowID: "1", groups: ["Kind"], sorts: ["Name"], hide: false).contains("do shell script"), "no file manipulation")
        do {
            let oldData = Data(#"{"grouping":"modified","sorting":"size","externalEnabled":false,"appearance":"dark","rules":[]}"#.utf8)
            let old = try JSONDecoder().decode(Preferences.self, from: oldData)
            check(old.grouping == .modified && old.sorting == .size && !old.externalEnabled && old.appearance == "dark" && old.language == "system", "old settings survive language upgrade")
            check(old.updateFrequency == .weekly, "existing settings receive weekly software updates by default")
            let unknownFrequency = try JSONDecoder().decode(Preferences.self, from: Data(#"{"updateFrequency":"future"}"#.utf8))
            check(unknownFrequency.updateFrequency == .weekly, "unrecognized software update frequency falls back safely")
            guard let englishPath = L.bundle("en")?.path(forResource: "Localizable", ofType: "strings"),
                  let english = NSDictionary(contentsOfFile: englishPath) as? [String: String] else { print("FAIL: English resources missing"); exit(1) }
            for language in AppLanguage.allCases where language != .system {
                guard let path = L.bundle(language.rawValue)?.path(forResource: "Localizable", ofType: "strings"),
                      let translations = NSDictionary(contentsOfFile: path) as? [String: String] else { print("FAIL: Missing locale \(language.rawValue)"); exit(1) }
                check(Set(translations.keys) == Set(english.keys) && translations.values.allSatisfy { !$0.isEmpty }, "complete translation table \(language.rawValue)")
                check(translations.allSatisfy { key, value in value.components(separatedBy: "%@").count == english[key]!.components(separatedBy: "%@").count }, "format placeholders \(language.rawValue)")
                L.language = language.rawValue
                check(L.resolved == language.rawValue && L.t("全局默认") == translations["全局默认"], "live locale selection \(language.rawValue)")
                check(L.direction == (language == .ar ? .rightToLeft : .leftToRight), "layout direction \(language.rawValue)")
            }
            L.language = "system"
        } catch { print("FAIL: localization or upgrade \(error)"); exit(1) }
        print("PASS: \(count) checks. Rules, device identity, persistence, Finder scripts, and all 13 locales verified.")
    }
}
