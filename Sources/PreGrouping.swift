import AppKit
import Foundation

/// Writes the grouping rules into Finder's own per-folder view records ahead of time, so a folder
/// opens already grouped (and in icon view) with nothing done after it appears. Finder keeps a
/// child folder's view settings in its parent's `.DS_Store` (code `GRP0` for Group By, `icvp` for
/// the icon view options, `vstl` for the view style). Files are only written while Finder is not
/// running, and every `.DS_Store` is backed up the first time it is changed so all of it can be
/// put back. Folders on other volumes are left alone: Finder does not keep these records there.
enum PreGrouping {
    /// Finder's stored names for "Group By"; read back from Finder for each menu choice.
    static func groupCode(_ grouping: Grouping) -> String? {
        switch grouping {
        case .name: return "Name"
        case .kind: return "Kind"
        case .opened: return "Date Last Opened"
        case .added: return "Date Added"
        case .modified: return "Date Modified"
        case .size: return "Size"
        case .tags: return "Finder Tags"
        case .created, .none: return nil
        }
    }
    static func arrangeBy(_ sorting: Sorting) -> String {
        switch sorting {
        case .name: return "name"
        case .kind: return "kind"
        case .modified: return "dateModified"
        case .created: return "dateCreated"
        case .added: return "dateAdded"
        case .opened: return "dateLastOpened"
        case .size: return "size"
        case .tags: return "label"
        }
    }

    struct Change: Codable { var path: String; var existed: Bool; var backup: String? }
    struct Manifest: Codable { var changes: [Change] = [] }
    struct Outcome { var folders = 0; var files = 0; var skipped = 0 }

    static var backupDirectory: URL { Storage.directory.appendingPathComponent("pregroup-backup") }
    static var manifestURL: URL { backupDirectory.appendingPathComponent("manifest.json") }
    static var canRestore: Bool { !(Storage.read(Manifest.self, from: manifestURL)?.changes.isEmpty ?? true) }

    private static let skippedNames: Set<String> = ["Library", "node_modules", "Pods", "DerivedData", "Applications"]

    /// Folders whose children get records: the roots and their subfolders, same volume only.
    static func parents(of roots: [URL], maxDepth: Int = 7, limit: Int = 20_000) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .volumeIdentifierKey]
        var result: [URL] = [], queue: [(URL, Int)] = roots.map { ($0, 0) }, seen = Set<String>()
        let volume = roots.first.flatMap { try? $0.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject }
        while !queue.isEmpty, result.count < limit {
            let (folder, depth) = queue.removeFirst()
            guard seen.insert(folder.standardizedFileURL.path).inserted else { continue }
            result.append(folder)
            guard depth < maxDepth else { continue }
            for child in subfolders(of: folder, keys: keys) {
                if let volume, (try? child.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject) != volume { continue }
                queue.append((child, depth + 1))
            }
        }
        return result
    }
    static func subfolders(of folder: URL, keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey]) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items.filter { item in
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
                  values.isPackage != true, values.isSymbolicLink != true, values.isHidden != true else { return false }
            return !skippedNames.contains(item.lastPathComponent)
        }
    }

    /// The icon view options Finder uses for new folders, as a starting point for new records.
    static func defaultIconOptions() -> [String: Any] {
        let finder = UserDefaults(suiteName: "com.apple.finder")
        let standard = finder?.dictionary(forKey: "StandardViewSettings")?["IconViewSettings"] as? [String: Any]
        return standard ?? ["arrangeBy": "name", "iconSize": 64.0, "gridSpacing": 54.0, "textSize": 12.0, "labelOnBottom": true,
                            "showItemInfo": false, "showIconPreview": true, "backgroundType": 0, "viewOptionsVersion": 1]
    }

    /// The records the children of `folder` should carry. Returns the changed file, or nil when
    /// nothing needs to change. Throws when the existing file cannot be read safely.
    static func plan(folder: URL, preferences: Preferences, iconSize: Int?, defaults: [String: Any]) throws -> (data: Data, folders: Int)? {
        let storeURL = folder.appendingPathComponent(".DS_Store")
        var store = DSStoreFile()
        if let existing = try? Data(contentsOf: storeURL) { store = try DSStoreFile(data: existing) }
        let volume = try? folder.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        var changed = 0
        for child in subfolders(of: folder) {
            let name = child.lastPathComponent
            let rule = RuleResolver.resolve(path: child.path, volumeID: volume, isExternal: false, preferences: preferences)
            guard !rule.excluded, let code = groupCode(rule.grouping) else { continue }
            var options = store.plist(name, "icvp") ?? defaults
            let arrange = arrangeBy(rule.sorting)
            let needsGroup = store.string(name, "GRP0") != code
            let needsArrange = options["arrangeBy"] as? String != arrange
            let needsSize = iconSize.map { (options["iconSize"] as? Double).map(Int.init) != $0 } ?? false
            let style = store.value(name, "vstl")
            let wanted = preferences.viewStyle.storeCode
            let needsIcons = wanted != nil && style != nil && style?.payload != DSStoreFile.typeCode(wanted!)
            guard needsGroup || needsArrange || needsSize || needsIcons || store.value(name, "icvp") == nil else { continue }
            options["arrangeBy"] = arrange
            if let iconSize { options["iconSize"] = Double(iconSize) }
            guard let encoded = try? PropertyListSerialization.data(fromPropertyList: options, format: .binary, options: 0) else { continue }
            store.set(name, "GRP0", type: "ustr", payload: DSStoreFile.ustr(code))
            store.set(name, "icvp", type: "blob", payload: DSStoreFile.blob(encoded))
            if store.value(name, "vSrn") == nil { store.set(name, "vSrn", type: "long", payload: DSStoreFile.long(1)) }
            if needsIcons, let wanted { store.set(name, "vstl", type: "type", payload: DSStoreFile.typeCode(wanted)) }
            changed += 1
        }
        guard changed > 0 else { return nil }
        let data = store.encoded()
        // Never write something this reader cannot read back to the same records.
        guard (try? DSStoreFile(data: data)) == store else { throw DSStoreFile.Failure.corrupt("verification") }
        return (data, changed)
    }

    /// Writes the planned records. Call only while Finder is not running.
    static func apply(parents: [URL], preferences: Preferences, iconSize: Int?) -> Outcome {
        var outcome = Outcome()
        var manifest = Storage.read(Manifest.self, from: manifestURL) ?? Manifest()
        var recorded = Set(manifest.changes.map(\.path))
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let defaults = defaultIconOptions()
        for folder in parents {
            let storeURL = folder.appendingPathComponent(".DS_Store")
            do {
                guard let planned = try plan(folder: folder, preferences: preferences, iconSize: iconSize, defaults: defaults) else { continue }
                if !recorded.contains(storeURL.path) {
                    let existed = FileManager.default.fileExists(atPath: storeURL.path)
                    var backupName: String?
                    if existed {
                        let name = UUID().uuidString + ".DS_Store"
                        try FileManager.default.copyItem(at: storeURL, to: backupDirectory.appendingPathComponent(name))
                        backupName = name
                    }
                    manifest.changes.append(Change(path: storeURL.path, existed: existed, backup: backupName))
                    recorded.insert(storeURL.path)
                    try Storage.save(manifest, to: manifestURL)
                }
                try planned.data.write(to: storeURL, options: .atomic)
                outcome.folders += planned.folders; outcome.files += 1
            } catch { outcome.skipped += 1 }
        }
        return outcome
    }

    /// Puts every changed `.DS_Store` back as it was. Call only while Finder is not running.
    static func restore() -> Int {
        guard let manifest = Storage.read(Manifest.self, from: manifestURL) else { return 0 }
        var restored = 0
        for change in manifest.changes {
            let target = URL(fileURLWithPath: change.path)
            if change.existed, let backup = change.backup {
                let source = backupDirectory.appendingPathComponent(backup)
                guard let data = try? Data(contentsOf: source), (try? data.write(to: target, options: .atomic)) != nil else { continue }
            } else {
                try? FileManager.default.removeItem(at: target)
            }
            restored += 1
        }
        try? FileManager.default.removeItem(at: backupDirectory)
        return restored
    }

    // MARK: Finder

    static var finderRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty }
    /// Asks Finder to quit and waits for it. Run on the Apple-event queue.
    static func quitFinder() -> Bool {
        _ = ScriptRunner.run("with timeout of 5 seconds\ntell application \"Finder\" to quit\nend timeout")
        for _ in 0..<80 where finderRunning { usleep(100_000) }
        return !finderRunning
    }
    static func launchFinder() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: finder, configuration: configuration)
        for _ in 0..<50 where !finderRunning { usleep(100_000) }
    }
}
