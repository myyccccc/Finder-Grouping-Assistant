import Foundation
import AppKit

enum Grouping: String, Codable, CaseIterable, Identifiable {
    case kind, name, modified, created, added, opened, size, tags, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kind: return L.t("文件种类")
        case .name: return L.t("名称")
        case .modified: return L.t("修改日期")
        case .created: return L.t("创建日期")
        case .added: return L.t("添加日期")
        case .opened: return L.t("上次打开日期")
        case .size: return L.t("文件大小")
        case .tags: return L.t("标签")
        case .none: return L.t("不分组")
        }
    }
    var symbol: String {
        switch self {
        case .kind: return "square.grid.2x2"
        case .name: return "textformat.abc"
        case .modified, .created, .added, .opened: return "calendar"
        case .size: return "arrow.up.arrow.down"
        case .tags: return "tag"
        case .none: return "list.bullet"
        }
    }
    var menuNames: [String] {
        switch self {
        case .kind: return ["Kind", "种类", "種類", "종류", "Art", "Dateityp", "Type", "Clase", "Tipo", "Тип", "النوع", "نوع", "प्रकार"]
        case .name: return ["Name", "名称", "名稱", "名前", "이름", "Nom", "Nombre", "Nome", "Имя", "الاسم", "नाम", "по имени"]
        case .modified: return ["Date Modified", "修改日期", "変更日", "수정일", "Änderungsdatum", "Date de modification", "Fecha de modificación", "Data de Modificação", "Data de modificação", "Data di modifica", "Дата изменения", "تاريخ التعديل", "बदलाव की तारीख", "Modificación", "संशोधन की तिथि"]
        case .created: return ["Date Created", "创建日期", "製作日期", "建立日期", "作成日", "생성일", "Erstellungsdatum", "Date de création", "Fecha de creación", "Data de Criação", "Data de criação", "Data di creazione", "Дата создания", "تاريخ الإنشاء", "बनाने की तारीख", "Creación", "बनाने की तिथि"]
        case .added: return ["Date Added", "添加日期", "加入日期", "追加日", "추가일", "Hinzugefügt am", "Hinzugefügt", "Date d’ajout", "Date d'ajout", "Fecha de adición", "Data de Adição", "Data de adição", "Data di aggiunta", "Дата добавления", "تاريخ الإضافة", "जोड़ने की तारीख", "추가된 날짜", "Date de l’ajout", "Fecha de inclusión", "Data da Adição", "जोड़ने की तिथि"]
        case .opened: return ["Date Last Opened", "上次打开日期", "上次開啟日期", "最後に開いた日", "最近使用日", "최근 사용일", "Zuletzt geöffnet", "Letzte Öffnung", "Date de dernière ouverture", "Dernière ouverture", "Fecha de última apertura", "Última apertura", "Data da Última Abertura", "Última abertura", "Data ultima apertura", "Ultima apertura", "Дата последнего открытия", "Последнее открытие", "تاريخ آخر فتح", "आखिरी बार खोलने की तारीख", "上次打開日期", "Fecha de la última apertura", "अंतिम बार खोलने की तिथि"]
        case .size: return ["Size", "大小", "サイズ", "크기", "Größe", "Taille", "Tamaño", "Tamanho", "Dimensioni", "Dimensione", "Размер", "الحجم", "حجم", "आकार"]
        case .tags: return ["Tags", "标签", "標籤", "タグ", "태그", "Étiquettes", "Etiquetas", "Tag", "Теги", "الوسوم", "وسوم", "टैग", "العلامات"]
        case .none: return ["None", "无", "無", "なし", "없음", "Ohne", "Keine", "Aucun", "Ninguno", "Nenhum", "Nessuno", "Нет", "لا شيء", "कोई नहीं"]
        }
    }
}

enum Sorting: String, Codable, CaseIterable, Identifiable {
    case name, kind, modified, created, added, opened, size, tags
    var id: String { rawValue }
    var grouping: Grouping { Grouping(rawValue: rawValue)! }
    var title: String { grouping.title }
    var menuNames: [String] { grouping.menuNames }
}

enum RuleScope: String, Codable, CaseIterable, Identifiable {
    case folder, device
    var id: String { rawValue }
    var title: String { self == .folder ? L.t("文件夹") : L.t("整个设备") }
}

struct LocationRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var volumeID: String?
    var scope: RuleScope = .folder
    var includeChildren = true
    var enabled = true
    var excluded = false
    var grouping: Grouping = .kind
    var sorting: Sorting = .name
    var bookmark: Data?
}

enum SoftwareUpdateFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, manual
    var id: String { rawValue }
    var title: String { switch self { case .daily: return L.t("每天"); case .weekly: return L.t("每周"); case .manual: return L.t("手动") } }
}

enum FeedbackReport {
    static func make(message: String, includeSystem: Bool) -> String {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includeSystem else { return message }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return message + "\n\nFinder Grouping Assistant " + version + "\nmacOS " + ProcessInfo.processInfo.operatingSystemVersionString
    }
}

struct Preferences: Codable, Equatable {
    var grouping: Grouping = .kind
    var sorting: Sorting = .name
    var internalEnabled = true
    var externalEnabled = true
    var hideOnNavigation = false
    var appearance = "system"
    var language = "system"
    var updateFrequency: SoftwareUpdateFrequency = .weekly
    var engineEnabled = false
    var hasCompletedSetup = false
    var rules: [LocationRule] = []
    /// The view folder windows are kept in; `.keep` leaves Finder's own choice alone.
    var viewStyle: ViewStyle = .icon
    var alwaysIconView: Bool { viewStyle == .icon }
    /// Icon size for icon-view windows; nil leaves Finder's own size alone.
    var iconSize: Int?
    static let iconSizeRange = 16...512
    init() {}
    enum CodingKeys: String, CodingKey { case updateFrequency, grouping, sorting, internalEnabled, externalEnabled, hideOnNavigation, appearance, language, engineEnabled, hasCompletedSetup, rules, alwaysIconView, viewStyle, iconSize }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grouping = try c.decodeIfPresent(Grouping.self, forKey: .grouping) ?? .kind
        sorting = try c.decodeIfPresent(Sorting.self, forKey: .sorting) ?? .name
        internalEnabled = try c.decodeIfPresent(Bool.self, forKey: .internalEnabled) ?? true
        externalEnabled = try c.decodeIfPresent(Bool.self, forKey: .externalEnabled) ?? true
        hideOnNavigation = try c.decodeIfPresent(Bool.self, forKey: .hideOnNavigation) ?? false
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        engineEnabled = try c.decodeIfPresent(Bool.self, forKey: .engineEnabled) ?? false
        // Preserve the explicit on/off choice of existing installations.
        hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? true
        updateFrequency = (try? c.decodeIfPresent(SoftwareUpdateFrequency.self, forKey: .updateFrequency)) ?? .weekly
        rules = try c.decodeIfPresent([LocationRule].self, forKey: .rules) ?? []
        // Versions before the view picker only stored whether icons were enforced.
        let legacyIcons = (try? c.decodeIfPresent(Bool.self, forKey: .alwaysIconView)) ?? true
        viewStyle = (try? c.decodeIfPresent(ViewStyle.self, forKey: .viewStyle)) ?? (legacyIcons ? .icon : .keep)
        iconSize = (try? c.decodeIfPresent(Int.self, forKey: .iconSize)).flatMap { $0 }.map { min(max($0, Self.iconSizeRange.lowerBound), Self.iconSizeRange.upperBound) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(grouping, forKey: .grouping); try c.encode(sorting, forKey: .sorting)
        try c.encode(internalEnabled, forKey: .internalEnabled); try c.encode(externalEnabled, forKey: .externalEnabled)
        try c.encode(hideOnNavigation, forKey: .hideOnNavigation); try c.encode(appearance, forKey: .appearance)
        try c.encode(language, forKey: .language); try c.encode(engineEnabled, forKey: .engineEnabled)
        try c.encode(hasCompletedSetup, forKey: .hasCompletedSetup); try c.encode(updateFrequency, forKey: .updateFrequency)
        try c.encode(rules, forKey: .rules); try c.encode(viewStyle, forKey: .viewStyle)
        // Kept so an older version reading this file still knows whether icons were enforced.
        try c.encode(alwaysIconView, forKey: .alwaysIconView)
        try c.encodeIfPresent(iconSize, forKey: .iconSize)
    }
}

/// How folder windows are shown. Anything other than `.keep` is restored whenever a window drifts.
enum ViewStyle: String, Codable, CaseIterable, Identifiable {
    case icon, list, column, gallery, keep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: return L.t("图标")
        case .list: return L.t("列表")
        case .column: return L.t("分栏")
        case .gallery: return L.t("画廊")
        case .keep: return L.t("不改变")
        }
    }
    var symbol: String {
        switch self {
        case .icon: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .column: return "rectangle.split.3x1"
        case .gallery: return "rectangle.grid.1x2"
        case .keep: return "minus.circle"
        }
    }
    /// The Finder scripting name used to switch a window to this view.
    var scriptName: String? {
        switch self {
        case .icon: return "icon view"
        case .list: return "list view"
        case .column: return "column view"
        case .gallery: return "flow view"
        case .keep: return nil
        }
    }
    /// Whether a window reporting `view` already shows this style.
    func matches(_ view: String) -> Bool {
        switch self {
        case .keep: return true
        case .gallery: return ["gallery view", "flow view", "group view"].contains(view)
        default: return view == scriptName
        }
    }
    /// The `vstl` code Finder stores for this view in a parent's .DS_Store (verified ones only).
    var storeCode: String? {
        switch self {
        case .icon: return "icnv"
        case .list: return "Nlsv"
        default: return nil
        }
    }
}

struct MountedVolume: Identifiable, Equatable {
    // Cloned disk images can expose the same UUID at different mount points.
    // UI identity is per mount; persistent device rules continue to use the UUID.
    var id: String { path }
    let name: String
    let path: String
    let uuid: String?
    let external: Bool
    let removable: Bool
    let readOnly: Bool
    let total: Int64
    let available: Int64
    var symbol: String { removable ? "sdcard" : "externaldrive" }
    static func discover() -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys), v.volumeIsInternal != true else { return nil }
            return MountedVolume(name: v.volumeName ?? url.lastPathComponent, path: url.path, uuid: v.volumeUUIDString,
                                 external: true, removable: v.volumeIsRemovable ?? false, readOnly: v.volumeIsReadOnly ?? false,
                                 total: Int64(v.volumeTotalCapacity ?? 0), available: Int64(v.volumeAvailableCapacity ?? 0))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct EffectiveRule: Equatable {
    let grouping: Grouping
    let sorting: Sorting
    let source: String
    let excluded: Bool
}

struct FinderPollingState {
    private(set) var failures = 0
    private(set) var nextQuery = Date.distantPast
    func canQuery(at date: Date) -> Bool { date >= nextQuery }
    mutating func failed(at date: Date) {
        failures = min(failures + 1, 4)
        nextQuery = date.addingTimeInterval(min(30, 2 * pow(2, Double(failures))))
    }
    mutating func succeeded() { failures = 0; nextQuery = .distantPast }
}

struct FinderHiddenRepairState {
    private var nextCheck = Date.distantPast
    func isDue(at date: Date) -> Bool { date >= nextCheck }
    mutating func didCheck(at date: Date) { nextCheck = date.addingTimeInterval(8) }
    mutating func failed(at date: Date) { nextCheck = date.addingTimeInterval(30) }
}

enum FinderViewSupport {
    static func supportsGrouping(in view: String) -> Bool {
        !["gallery view", "flow view", "group view"].contains(view)
    }
    static func grouping(_ requested: Grouping, in view: String) -> Grouping {
        supportsGrouping(in: view) ? requested : .none
    }
}

struct FinderNavigationGate {
    private var signature: String?
    private var revision: UInt64?
    private var lastQuery = Date.distantPast
    func shouldQuery(signature next: String?, revision nextRevision: UInt64, at date: Date) -> Bool {
        if revision != nextRevision { return true }
        if let next { return signature != next }
        // Some Finder views do not expose AXDocument. Keep a slower fallback.
        return date.timeIntervalSince(lastQuery) >= 10
    }
    mutating func record(signature: String?, revision: UInt64, at date: Date) {
        self.signature = signature; self.revision = revision; lastQuery = date
    }
}

enum AutomationPermissionState: Equatable {
    case allowed, denied, unknown
    static func resolve(_ statuses: [Int32]) -> Self {
        if statuses.contains(-1743) || statuses.contains(-1744) { return .denied }
        return statuses.allSatisfy { $0 == 0 } ? .allowed : .unknown
    }
}

struct FinderPermissionSnapshot {
    var accessibility: Bool
    var automation: AutomationPermissionState
    var available = true
}

struct FinderLocation {
    let urlString: String
    let path: String
    let windowID: String
    let view: String
    let volumeID: String?
    let isExternal: Bool
    /// Icon size of an icon-view window, when Finder reports it.
    var iconSize: Int? = nil
    // File-system metadata is read on the Apple-event worker, never the UI thread.
    static func inspect(_ descriptor: NSAppleEventDescriptor) -> FinderLocation? {
        guard descriptor.numberOfItems >= 2, let urlString = descriptor.atIndex(1)?.stringValue,
              let url = URL(string: urlString), url.isFileURL,
              let windowID = descriptor.atIndex(2)?.stringValue,
              let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsInternalKey, .isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true else { return nil }
        var location = FinderLocation(urlString: urlString, path: url.standardizedFileURL.path, windowID: windowID,
                              view: descriptor.atIndex(3)?.stringValue ?? "", volumeID: values.volumeUUIDString,
                              isExternal: values.volumeIsInternal == false)
        if descriptor.numberOfItems >= 4, let size = descriptor.atIndex(4)?.stringValue.flatMap({ Double($0) }), size > 0 { location.iconSize = Int(size.rounded()) }
        return location
    }
}

enum RuleResolver {
    static func matchesDevice(_ rule: LocationRule, uuid: String?, path: String) -> Bool {
        guard rule.scope == .device else { return false }
        if let knownID = rule.volumeID { return knownID == uuid }
        return normalized(rule.path) == normalized(path)
    }
    static func normalized(_ path: String) -> String {
        let value = URL(fileURLWithPath: path).standardizedFileURL.path
        return value.count > 1 && value.hasSuffix("/") ? String(value.dropLast()) : value
    }
    static func contains(_ root: String, _ path: String) -> Bool {
        let a = normalized(root), b = normalized(path)
        return a == b || b.hasPrefix(a == "/" ? "/" : a + "/")
    }
    static func resolve(path: String, volumeID: String?, isExternal: Bool, preferences: Preferences) -> EffectiveRule {
        // Scope switches apply to every rule, including folder and device overrides.
        if isExternal ? !preferences.externalEnabled : !preferences.internalEnabled {
            return EffectiveRule(grouping: preferences.grouping, sorting: preferences.sorting, source: L.t("此位置已排除"), excluded: true)
        }
        let folder = preferences.rules.filter { rule in
            guard rule.enabled, rule.scope == .folder else { return false }
            return rule.includeChildren ? contains(rule.path, path) : normalized(rule.path) == normalized(path)
        }.sorted { normalized($0.path).count > normalized($1.path).count }.first
        let device = preferences.rules.first { rule in
            guard rule.enabled, rule.scope == .device else { return false }
            if let knownID = rule.volumeID { return knownID == volumeID }
            return contains(rule.path, path)
        }
        if let rule = folder ?? device {
            return EffectiveRule(grouping: rule.grouping, sorting: rule.sorting, source: rule.name, excluded: rule.excluded)
        }
        return EffectiveRule(grouping: preferences.grouping, sorting: preferences.sorting, source: L.t("全局默认"), excluded: isExternal ? !preferences.externalEnabled : !preferences.internalEnabled)
    }
}

struct ActivityEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var title: String
    var detail: String
    var path: String?
    var success = true
    var previousGroup: String?
    var previousSort: String?
    var windowID: String?
}

struct OriginalFinderLayout: Codable, Equatable {
    var path: String
    var view: String
    var volumeID: String?
    var group: String
    var sort: String
}

struct FinderLayoutArchive: Codable {
    var originals: [String: OriginalFinderLayout] = [:]
    var confirmed: [String: String] = [:]
    static func key(path: String, view: String, volumeID: String?) -> String {
        RuleResolver.normalized(path) + "\n" + view + "\n" + (volumeID ?? "")
    }
    static func fingerprint(group: Grouping, sort: Sorting, hide: Bool) -> String {
        group.rawValue + ":" + sort.rawValue + ":" + String(hide)
    }
    mutating func remember(_ original: OriginalFinderLayout, fingerprint: String?) {
        let key = Self.key(path: original.path, view: original.view, volumeID: original.volumeID)
        if originals[key] == nil, !original.group.isEmpty, !original.sort.isEmpty { originals[key] = original }
        if let fingerprint { confirmed[key] = fingerprint }
    }
    func original(path: String, view: String, volumeID: String?) -> OriginalFinderLayout? {
        let normalized = RuleResolver.normalized(path)
        let legacy = RuleResolver.contains("/Volumes", normalized) ? nil : originals[Self.key(path: path, view: "*", volumeID: nil)]
        return originals[Self.key(path: path, view: view, volumeID: volumeID)]
            ?? originals[Self.key(path: path, view: "*", volumeID: volumeID)] ?? legacy
    }
    mutating func forgetConfirmation(path: String) {
        let prefix = RuleResolver.normalized(path) + "\n"
        confirmed = confirmed.filter { !$0.key.hasPrefix(prefix) }
    }
}

enum FinderVisibilityPreference {
    static func bool(_ value: Any?) -> Bool {
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["1", "true", "yes"].contains(value.lowercased()) }
        return false
    }
    static var showsHiddenFiles: Bool {
        let domain = "com.apple.finder" as CFString
        CFPreferencesAppSynchronize(domain)
        return bool(CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, domain))
    }
}

enum PreferenceImport {
    static func validate(_ prefs: Preferences) -> Bool {
        guard prefs.rules.count <= 500, Set(prefs.rules.map(\.id)).count == prefs.rules.count,
              ["system", "light", "dark"].contains(prefs.appearance),
              AppLanguage.allCases.contains(where: { $0.rawValue == prefs.language }) else { return false }
        return prefs.rules.allSatisfy { rule in
            rule.path.hasPrefix("/") && !rule.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }
    }
    static func portable(_ prefs: Preferences) -> Preferences {
        var portable = prefs; portable.engineEnabled = false
        portable.rules = portable.rules.map { var rule = $0; rule.bookmark = nil; return rule }
        return portable
    }
}

enum Storage {
    static let directory: URL = {
        if CommandLine.arguments.contains("--permission-flow-test") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("FinderPermissionFlowTests-" + UUID().uuidString)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FinderGroupingAssistant")
    }()
    static var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }
    static var layoutsURL: URL { directory.appendingPathComponent("finder-layouts.json") }
    static var activityURL: URL { directory.appendingPathComponent("activity.json") }
    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum PersistenceWriter {
    private static let queue = DispatchQueue(label: "FinderGroupingAssistant.persistence", qos: .utility)
    private static var pending: [URL: () -> Void] = [:]
    private static var scheduled = false
    static func save<T: Encodable>(_ value: T, to url: URL, onError: @escaping (Error) -> Void) {
        queue.async {
            pending[url] = {
                do { try Storage.save(value, to: url) }
                catch { DispatchQueue.main.async { onError(error) } }
            }
            guard !scheduled else { return }
            scheduled = true
            queue.asyncAfter(deadline: .now() + 0.15) { drain() }
        }
    }
    private static func drain() {
        let jobs = pending.values.map { $0 }
        pending.removeAll(); scheduled = false
        for job in jobs { job() }
    }
    static func flush(completion: @escaping () -> Void) {
        queue.async { drain(); DispatchQueue.main.async(execute: completion) }
    }
    static func flushForTests() { queue.sync { drain() } }
}

func readablePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

func formattedBytes(_ value: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var amount = Double(value), unit = 0
    while amount >= 1000, unit < units.count - 1 { amount /= 1000; unit += 1 }
    let formatter = NumberFormatter(); formatter.locale = L.locale; formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 2
    return (formatter.string(from: NSNumber(value: amount)) ?? String(amount)) + " " + units[unit]
}
