import Combine
import Foundation
#if canImport(SignalStatus)
@testable import SignalStatus
#endif

enum EfficiencyRegression {
    static func run() async -> [String] {
        var failures = await MainActor.run { modelChecks() }
        let route = ZTEHTTPRoute(interfaceName: "en9", interfaceIndex: 9, sourceAddress: "192.0.2.2")
        let directory = ZTEInterfaceDirectory<String>()
        do {
            async let pending: [String] = withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<20 { group.addTask { try await directory.resolve(route, timeout: 1) } }
                var results: [String] = []
                for try await value in group { results.append(value) }
                return results
            }
            try await Task.sleep(nanoseconds: 20_000_000)
            directory.update([ZTEAvailableInterface(name: "en9", index: 9, value: "first")])
            let results = try await pending
            if results.count != 20 || results.contains(where: { $0 != "first" }) {
                failures.append("concurrent interface waiters must share the first snapshot")
            }
            for _ in 0..<100 {
                if try await directory.resolve(route, timeout: 0) != "first" {
                    failures.append("repeated interface lookup must reuse the current snapshot")
                }
            }
            directory.update([ZTEAvailableInterface(name: "en9", index: 12, value: "replacement")])
            do {
                _ = try await directory.resolve(route, timeout: 0)
                failures.append("a replaced interface index must not use the old cached route")
            } catch ZTEUBusError.interfaceUnavailable { }
            let nextRoute = ZTEHTTPRoute(interfaceName: "en9", interfaceIndex: 12, sourceAddress: nil)
            if try await directory.resolve(nextRoute, timeout: 0) != "replacement" {
                failures.append("replacement interface must be resolved from the new snapshot")
            }
            let wrongName = ZTEHTTPRoute(interfaceName: "en1", interfaceIndex: 12, sourceAddress: nil)
            do {
                _ = try await directory.resolve(wrongName, timeout: 0)
                failures.append("interface name and index must both match")
            } catch ZTEUBusError.interfaceUnavailable { }
            directory.update([])
            do {
                _ = try await directory.resolve(nextRoute, timeout: 0)
                failures.append("removed interfaces must invalidate the cache immediately")
            } catch ZTEUBusError.interfaceUnavailable { }
            let empty = ZTEInterfaceDirectory<String>()
            do {
                _ = try await empty.resolve(route, timeout: 0.01)
                failures.append("initial interface wait must have a bounded timeout")
            } catch ZTEUBusError.interfaceUnavailable { }
            let cancelled = Task { try await empty.resolve(route, timeout: 1) }
            try await Task.sleep(nanoseconds: 10_000_000)
            cancelled.cancel()
            do {
                _ = try await cancelled.value
                failures.append("cancelled interface waiter must not complete successfully")
            } catch is CancellationError { }
            // A late path event/deadline must not resume cancelled waiters twice.
            empty.update([ZTEAvailableInterface(name: "en9", index: 9, value: "late")])
        } catch {
            failures.append("interface directory regression: \(error)")
        }
        return failures
    }

    @MainActor
    private static func modelChecks() -> [String] {
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) { if !value { failures.append(message) } }
        let suite = "EfficiencyRegression.\(UUID().uuidString)"
        let defaults = EfficiencyCountingDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = StatusModel(defaults: defaults, credentialStore: EfficiencyCredentials(), demoSnapshot: .empty)
        let modem = ActiveModem(
            identity: ModemIdentity(kind: .zteMC7530CA, manufacturer: "ZTE", model: "MC7530CA", stableIdentifier: "offline-efficiency"),
            endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.0.2.1")!, interfaceName: "en9", interfaceIndex: 9),
            capabilities: [.statusRead]
        )
        var sample = DeviceSnapshot.empty
        sample.host = "192.0.2.1"
        sample.interfaceName = "en9"
        sample.nrSystemMode = .sa
        sample.nrBand = "n77"
        sample.nrSignal.rsrpDBm = -100
        sample.updatedAt = Date()
        func commit(_ sample: DeviceSnapshot) {
            model.applyReadResult(ModemReadResult(activeModem: modem, snapshot: sample,
                                                 reusedActiveEndpoint: true, discoveryReport: nil))
        }
        commit(sample)
        let firstWrites = defaults.writes
        let consumer = UUID()
        model.radioSnapshots.setVisible(true, consumer: consumer)
        var rootChanges = 0
        var signalChanges = 0
        let rootToken = model.objectWillChange.sink { rootChanges += 1 }
        let signalToken = model.radioSnapshots.objectWillChange.sink { signalChanges += 1 }
        sample.updatedAt = sample.updatedAt.addingTimeInterval(1)
        commit(sample)
        check(rootChanges == 0 && signalChanges == 0, "timestamp-only sample must not redraw the UI")
        check(model.snapshot.updatedAt == sample.updatedAt, "latest timestamp must remain exact for stale status and Copy")
        sample.nrSignal.rsrpDBm = -99
        commit(sample)
        check(rootChanges == 0 && signalChanges == 1, "signal changes must notify only the live radio subtree")
        check(defaults.writes == firstWrites, "identical endpoints must not be encoded/written again")
        model.radioSnapshots.setPanelVisible(false)
        sample.nrSignal.rsrpDBm = -98
        commit(sample)
        check(signalChanges == 1 && model.snapshot.nrSignal.rsrpDBm == -98, "hidden panel must retain samples without redraw notifications")
        model.radioSnapshots.setPanelVisible(true)
        check(signalChanges == 2, "reopening must notify consumers of the latest snapshot")
        model.radioSnapshots.setVisible(false, consumer: consumer)
        sample.nrSignal.rsrpDBm = -97
        commit(sample)
        check(signalChanges == 2, "unmounted radio consumers must not schedule redraws")
        sample.operatorName = "Fixture operator"
        commit(sample)
        check(rootChanges > 0, "operator and device metadata changes must still update the header")
        let activity = model.refreshActivity
        let rootsBeforeActivity = rootChanges
        activity.isRefreshing = true
        activity.beginManualRequest()
        activity.endManualRequest()
        activity.isRefreshing = false
        check(rootChanges == rootsBeforeActivity, "refresh activity must not invalidate the whole panel")
        check(activity.manualRequests == 0, "manual refresh indicator must stop after the request ends")
        withExtendedLifetime((rootToken, signalToken)) {}
        return failures
    }
}

private final class EfficiencyCountingDefaults: UserDefaults, @unchecked Sendable {
    var writes = 0
    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }
}

private final class EfficiencyCredentials: CredentialStoring {
    func password(for account: String) throws -> String? { nil }
    func setPassword(_ password: String, for account: String) throws { }
    func removePassword(for account: String) throws { }
}
