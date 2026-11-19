import Foundation
import AppKit
import Combine

enum PermissionFlowTests {
    final class Probe {
        private let lock = NSLock()
        private var value = FinderPermissionSnapshot(accessibility: false, automation: .denied)
        var gate: DispatchSemaphore?
        func set(_ snapshot: FinderPermissionSnapshot) { lock.lock(); value = snapshot; lock.unlock() }
        func read() -> FinderPermissionSnapshot {
            gate?.wait()
            lock.lock(); defer { lock.unlock() }; return value
        }
    }
    static func run() {
        var count = 0
        var models: [AppModel] = []
        func check(_ condition: Bool, _ text: String) {
            guard condition else { print("FAIL: permission flow: " + text); exit(1) }
            count += 1
        }
        func wait(_ condition: () -> Bool, seconds: Double = 4) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition() && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return condition()
        }
        func model(_ prefs: Preferences, _ probe: Probe) -> AppModel {
            let result = AppModel(preferences: prefs, permissionReader: probe.read,
                automationVerifier: { .success(NSAppleEventDescriptor(boolean: true)) }, prepareEnvironment: false)
            models.append(result); return result
        }
        let ready = FinderPermissionSnapshot(accessibility: true, automation: .allowed)
        var legacy = Preferences(); legacy.hasCompletedSetup = true
        let firstProbe = Probe(); let first = model(Preferences(), firstProbe)
        check(wait { first.permissionsChecked && first.showSetup }, "fresh install opens setup for missing permissions")
        var repeatedPresentation = 0
        let presentation = first.$showSetup.dropFirst().sink { if $0 { repeatedPresentation += 1 } }
        first.refreshEnvironment(includeVolumes: false)
        check(wait { !first.permissionChecking }, "denied permission refresh completes while setup is open")
        check(repeatedPresentation == 0, "unchanged setup is not presented again and cannot recursively restart permission checks")
        presentation.cancel()
        firstProbe.set(ready)
        check(wait { first.preferences.engineEnabled && !first.showSetup }, "granting permissions automatically enables and returns home")
        check(first.preferences.hasCompletedSetup, "successful onboarding is saved")
        check(first.isRunning, "main toggle becomes on only when grouping can run")
        first.pause()
        let reopenedProbe = Probe(); reopenedProbe.set(ready); let reopened = model(first.preferences, reopenedProbe)
        check(wait { reopened.permissionsChecked && !reopened.permissionChecking }, "reopen reads current permission state")
        check(!reopened.preferences.engineEnabled, "explicit pause survives relaunch")
        reopenedProbe.set(FinderPermissionSnapshot(accessibility: false, automation: .unknown, available: false))
        reopened.refreshEnvironment(includeVolumes: false)
        check(wait { !reopened.permissionChecking }, "sleep state does not leave permission checking stuck")
        check(reopened.accessibilityGranted && reopened.automationGranted && !reopened.showSetup, "sleep never overwrites confirmed grants with false denials")
        reopenedProbe.set(ready); reopened.refreshEnvironment(includeVolumes: false)
        check(wait { !reopened.permissionChecking && reopened.accessibilityGranted }, "wake refreshes current grants")

        let staleProbe = Probe(); staleProbe.set(ready); let stale = model(legacy, staleProbe)
        check(wait { stale.permissionsChecked && !stale.permissionChecking }, "legacy settings retain their existing state")
        stale.accessibilityGranted = false
        stale.start()
        check(wait { stale.preferences.engineEnabled && !stale.showSetup }, "start waits for fresh grant instead of using cached false")
        stale.pause(); stale.showPermissionSetup()
        check(wait { !stale.permissionChecking && !stale.showSetup }, "permission inspection closes when grants are already valid")
        check(!stale.preferences.engineEnabled, "inspection does not override a deliberate pause")

        let unknownProbe = Probe(); unknownProbe.set(FinderPermissionSnapshot(accessibility: true, automation: .unknown))
        let unknown = model(legacy, unknownProbe)
        check(wait { unknown.permissionsChecked && !unknown.permissionChecking }, "unavailable passive permissions settle without a consent prompt")
        check(!unknown.automationGranted && !unknown.preferences.engineEnabled, "unknown permissions are not fabricated or used to resume grouping")
        unknown.preferences.engineEnabled = true
        check(!unknown.isRunning, "saved enable intent never shows a running switch without grants")
        unknown.preferences.engineEnabled = false
        unknown.start()
        check(wait { !unknown.permissionChecking && unknown.showSetup }, "unavailable target waits without creating a consent dialog")
        check(!unknown.preferences.engineEnabled, "unavailable target is not falsely enabled")
        unknownProbe.set(ready)
        check(wait { unknown.automationGranted && unknown.preferences.engineEnabled }, "pending activation completes when the target becomes available")

        let cancelProbe = Probe(); cancelProbe.set(ready); let canceled = model(legacy, cancelProbe)
        check(wait { canceled.permissionsChecked && !canceled.permissionChecking }, "cancellation fixture ready")
        let gate = DispatchSemaphore(value: 0); cancelProbe.gate = gate
        canceled.start(); canceled.pause(); cancelProbe.gate = nil; gate.signal()
        check(wait { !canceled.permissionChecking }, "in-flight refresh settles after pause")
        check(!canceled.preferences.engineEnabled, "late permission result cannot undo pause")

        let laterProbe = Probe(); let later = model(Preferences(), laterProbe)
        check(wait { later.showSetup }, "deferred setup visible")
        later.cancelPermissionSetup(); laterProbe.set(ready); later.refreshEnvironment(includeVolumes: false)
        check(wait { !later.permissionChecking }, "deferred grant is read")
        check(!later.preferences.engineEnabled && !later.showSetup, "Later cancels pending activation")

        let savedProbe = Probe(); var savedPreferences = legacy; savedPreferences.engineEnabled = true
        let saved = model(savedPreferences, savedProbe)
        check(wait { saved.showSetup && !saved.permissionChecking }, "saved activation with missing grants opens setup")
        saved.cancelPermissionSetup(); saved.refreshEnvironment(includeVolumes: false)
        check(wait { !saved.permissionChecking }, "deferred saved activation refresh settles")
        check(!saved.preferences.engineEnabled && !saved.showSetup, "Later also cancels saved activation and does not reopen setup")

        check(!Preferences().hasCompletedSetup, "new preferences enter onboarding")
        let decoded = try! JSONDecoder().decode(Preferences.self, from: Data("{\"engineEnabled\":false}".utf8))
        check(decoded.hasCompletedSetup && !decoded.engineEnabled, "old paused preferences are preserved on upgrade")
        let encoded = try! JSONEncoder().encode(first.preferences)
        check((try! JSONDecoder().decode(Preferences.self, from: encoded)).hasCompletedSetup, "completed setup survives save and load")
        for model in models { model.prepareForQuit {} }
        var flushed = false; PersistenceWriter.flush { flushed = true }
        check(wait { flushed }, "test writes flush in isolated temporary storage")
        try? FileManager.default.removeItem(at: Storage.directory)
        print("PASS: \(count) asynchronous permission-flow checks. Real AppModel paths; production settings untouched.")
    }
}
