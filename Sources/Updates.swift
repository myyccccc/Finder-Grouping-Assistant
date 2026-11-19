import AppKit
import Foundation

/// Release pointer, uploaded as an asset of every GitHub release.
struct ReleaseInfo: Decodable {
    var version: String
    var build: Int
    var url: URL
    var page: URL?
}

/// Checks GitHub Releases for a newer direct-download release. Only the public pointer is
/// requested; no rules, paths or device details are sent.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let feed = URL(string: "https://github.com/myyccccc/Finder-Grouping-Assistant/releases/latest/download/finder-latest.json")!
    private let lastCheckKey = "SoftwareUpdate.lastCheck"
    private let notifiedBuildKey = "SoftwareUpdate.notifiedBuild"
    private var timer: Timer?
    private var checking = false

    static var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    static func interval(for frequency: SoftwareUpdateFrequency) -> TimeInterval? {
        switch frequency { case .daily: return 86_400; case .weekly: return 604_800; case .manual: return nil }
    }

    /// Automatic checks follow the chosen frequency; re-evaluated hourly while running.
    func start(frequency: @escaping () -> SoftwareUpdateFrequency) {
        let tick = { [weak self] in
            guard let self, let interval = Self.interval(for: frequency()) else { return }
            let last = UserDefaults.standard.double(forKey: self.lastCheckKey)
            if Date().timeIntervalSince1970 - last >= interval { self.check(userInitiated: false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: tick)
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { _ in tick() }
    }

    func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Self.feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("FinderGroupingAssistant/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap { try? JSONDecoder().decode(ReleaseInfo.self, from: $0) } : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if release != nil { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey) }
                self.present(release, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func present(_ release: ReleaseInfo?, userInitiated: Bool) {
        guard let release, release.url.scheme == "https" else {
            if userInitiated { alert(L.t("无法检查更新"), L.t("请检查网络连接后再试。"), buttons: [L.t("好")]) }
            return
        }
        guard release.build > Self.currentBuild else {
            if userInitiated { alert(L.t("已是最新版本"), L.f("Finder 分组助手 %@ 是目前的最新版本。", Self.currentVersion), buttons: [L.t("好")]) }
            return
        }
        // Automatic checks mention each new build once; a manual check always answers.
        if !userInitiated && UserDefaults.standard.integer(forKey: notifiedBuildKey) >= release.build { return }
        UserDefaults.standard.set(release.build, forKey: notifiedBuildKey)
        let choice = alert(L.f("Finder 分组助手 %@ 已推出", release.version),
                           L.f("当前版本为 %@。下载后打开安装包，将新版拖入“应用程序”替换即可，规则和设置会保留。", Self.currentVersion),
                           buttons: [L.t("下载新版"), L.t("以后再说")])
        if choice == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) }
    }

    @discardableResult
    private func alert(_ title: String, _ text: String, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
