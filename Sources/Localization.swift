import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ja, ko, de, fr, es, ptBR = "pt-BR", it, ru, ar, hi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L.t("跟随系统")
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .ptBR: return "Português (Brasil)"
        case .it: return "Italiano"
        case .ru: return "Русский"
        case .ar: return "العربية"
        case .hi: return "हिन्दी"
        }
    }
}

enum L {
    private static let lock = NSLock()
    private static var selectedLanguage = "system"
    private static var bundles: [String: Bundle] = [:]
    static var language: String {
        get { lock.lock(); defer { lock.unlock() }; return selectedLanguage }
        set { lock.lock(); selectedLanguage = newValue; lock.unlock() }
    }
    static var resolved: String {
        let selected = language
        if selected != "system", AppLanguage(rawValue: selected) != nil { return selected }
        for item in Locale.preferredLanguages {
            if item.hasPrefix("zh") { return item.contains("Hant") || item.contains("TW") || item.contains("HK") ? "zh-Hant" : "zh-Hans" }
            if item.hasPrefix("pt") { return "pt-BR" }
            let base = item.split(separator: "-").first.map(String.init) ?? "en"
            if AppLanguage(rawValue: base) != nil, base != "system" { return base }
        }
        return "en"
    }
    static var locale: Locale { Locale(identifier: resolved) }
    static var direction: LayoutDirection { resolved == "ar" ? .rightToLeft : .leftToRight }
    static func bundle(_ language: String) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let cached = bundles[language] { return cached }
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        bundles[language] = bundle
        return bundle
    }
    static func t(_ key: String) -> String {
        let value = bundle(resolved)?.localizedString(forKey: key, value: nil, table: "Localizable") ?? key
        if value != key || resolved == "zh-Hans" { return value }
        return bundle("en")?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }
    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: arguments)
    }
    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
