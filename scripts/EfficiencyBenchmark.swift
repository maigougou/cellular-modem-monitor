import AppKit
import Combine
import Darwin
import SwiftUI

private final class BenchmarkCredentials: CredentialStoring {
    func password(for account: String) throws -> String? { nil }
    func setPassword(_ password: String, for account: String) throws { }
    func removePassword(for account: String) throws { }
}

/// Offline rendering comparison. Uses the real panel with identical synthetic
/// 1 Hz samples, no modem requests, no speed tests, and an isolated defaults suite.
@main
enum EfficiencyBenchmark {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "EfficiencyBenchmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = StatusModel(defaults: defaults, credentialStore: BenchmarkCredentials(), demoSnapshot: .empty)
        let modem = ActiveModem(
            identity: ModemIdentity(kind: .zteMC7530CA, manufacturer: "ZTE", model: "MC7530CA", stableIdentifier: "offline-benchmark"),
            endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.0.2.1")!, interfaceName: "offline0", interfaceIndex: 999),
            capabilities: [.statusRead]
        )
        var sample = DeviceSnapshot.empty
        sample.host = "192.0.2.1"
        sample.interfaceName = "offline0"
        sample.operatorName = "Offline UI benchmark"
        sample.mcc = "302"
        sample.mnc = "220"
        sample.nrSystemMode = .nsa
        sample.nrBand = "n77"
        sample.nrChannel = "640608"
        sample.nrBandwidthMHz = 50
        sample.nrSignal = RadioSignal(rsrpDBm: -100, rsrqDB: -11, rssiDBm: -90, snrDB: 18)
        sample.lteBand = "B2"
        sample.lteChannel = "900"
        sample.lteBandwidthMHz = 20
        sample.lteSignal = RadioSignal(rsrpDBm: -95, rsrqDB: -12, rssiDBm: -80, snrDB: 10)
        sample.updatedAt = Date()
        func commit() {
            let result = ModemReadResult(activeModem: modem, snapshot: sample, reusedActiveEndpoint: true, discoveryReport: nil)
#if BASELINE_PERFORMANCE
            // The same successful-read assignments used in the v1.5.8 polling
            // path. Access is relaxed only in the throwaway source copy.
            model.snapshot = sample
            model.activeModem = modem
            model.persistLastSuccessful(result)
            model.connectionState = .online
            model.lastError = nil
            model.updateMenuTitle(force: false)
#else
            model.applyReadResult(result)
#endif
        }
        commit()
        let host = NSHostingView(rootView: StatusPanel(panelHeightLimit: 1000)
            .environmentObject(model)
            .environmentObject(SoftwareUpdater())
            .environment(\.appLanguage, .english)
            .preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 950),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Offline performance test — no modem connection"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        var notifications = 0
        let token = model.objectWillChange.sink { notifications += 1 }
#if !BASELINE_PERFORMANCE
        var radioNotifications = 0
        let radioToken = model.radioSnapshots.objectWillChange.sink { radioNotifications += 1 }
#endif
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            for phase in ["visible", "hidden"] {
                if phase == "hidden" {
                    window.orderOut(nil)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                notifications = 0
#if !BASELINE_PERFORMANCE
                radioNotifications = 0
#endif
                let cpuStart = cpuSeconds()
                let wallStart = ProcessInfo.processInfo.systemUptime
                for tick in 0..<15 {
                    model.isRefreshing = true
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    sample.updatedAt = Date()
                    sample.nrSignal.rsrpDBm = -100 + tick % 3
                    sample.nrSignal.snrDB = 18 + Double(tick % 3) / 10
                    commit()
                    model.isRefreshing = false
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
                let wall = ProcessInfo.processInfo.systemUptime - wallStart
                let cpu = cpuSeconds() - cpuStart
                print(String(format: "%@\t%.3f\t%.3f\t%.2f\t%d", phase, wall, cpu, 100 * cpu / wall, notifications))
#if !BASELINE_PERFORMANCE
                print("Radio notifications (\(phase)): \(radioNotifications)")
                if phase == "hidden" { precondition(radioNotifications == 0) }
#endif
                if phase == "visible", CommandLine.arguments.count > 1 {
                    host.layoutSubtreeIfNeeded()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(
                            to: URL(fileURLWithPath: CommandLine.arguments[1]))
                    }
                }
            }
            withExtendedLifetime(token) {}
#if !BASELINE_PERFORMANCE
            radioNotifications = 0
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            precondition(radioNotifications > 0, "Reopening must invalidate the retained radio view")
            precondition(model.snapshot.nrSignal.rsrpDBm == -98)
            print("Reopen: latest sample retained and visible radio content notified")
            withExtendedLifetime(radioToken) {}
#endif
            defaults.removePersistentDomain(forName: suite)
            app.terminate(nil)
        }
        app.run()
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
            Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}
