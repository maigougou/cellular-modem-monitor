import Combine
import Foundation
#if canImport(SignalStatus)
@testable import SignalStatus
#endif

enum MenuBarCARegression {
    @MainActor
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ label: String) {
            if !condition { failures.append("Menu bar CA: \(label)") }
        }
        var sample = fixture()
        check(sample.menuBarCarrierCounts == MenuBarCarrierCounts(nr: 3, lte: 2),
              "count carriers, not unique bands; exclude inactive and unknown states")
        check(sample.menuBarText(style: .detailed)
              == MenuBarText(primary: "NSA n77 · 3CC", secondary: "LTE B7 · 2CC"),
              "NSA has separate NR and LTE lines, not a combined cross-RAT CA total")
        check(sample.menuBarText(style: .compact)
              == MenuBarText(primary: "n77 · 3CC", secondary: "B7 · 2CC"), "compact two-line label")
        check(sample.menuBarText(style: .iconOnly) == MenuBarText(primary: ""), "icon-only stays text-free")
        check(sample.menuBarText(style: .detailed, countsAreFresh: false)
              == MenuBarText(primary: "NSA n77 · —", secondary: "LTE B7 · —"), "stale counts are not current CA")

        sample.nrSystemMode = .sa
        check(sample.menuBarCarrierCounts.lte == nil
              && sample.menuBarText(style: .detailed) == MenuBarText(primary: "SA n77 · 3CC"),
              "SA hides the whole LTE line even if LTE carrier data is stale")
        check(sample.menuBarText(style: .compact) == MenuBarText(primary: "n77 · 3CC"),
              "compact SA has no blank second line")
        sample.nrBand = nil
        check(sample.menuBarText(style: .detailed).secondary.isEmpty
              && !sample.menuBarText(style: .detailed).primary.contains("LTE"),
              "SA never falls back to stale LTE while NR is temporarily missing")
        sample.nrSystemMode = nil
        check(sample.menuBarText(style: .detailed) == MenuBarText(primary: "LTE B7 · 2CC"),
              "LTE-only uses a single row")
        sample = fixture()
        sample.nrSystemMode = nil
        check(sample.menuBarText(style: .detailed).primary == "NR n77 · 3CC", "do not infer NSA")
        sample.nrSecondaryCells = []
        sample.lteSecondaryCells = []
        check(sample.menuBarText(style: .detailed)
              == MenuBarText(primary: "NR n77 · 1CC", secondary: "LTE B7 · 1CC"),
              "one NR and one LTE carrier is not 2CC CA")
        sample.nrPrimaryCell = nil
        sample.ltePrimaryCell = nil
        check(sample.menuBarText(style: .detailed)
              == MenuBarText(primary: "NR n77 · —", secondary: "LTE B7 · —"),
              "missing carrier details do not invent a count")
        check(DeviceSnapshot.empty.menuBarText(style: .detailed).secondary.isEmpty,
              "searching has no stale second line")

        let suite = "MenuBarCARegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = StatusModel(defaults: defaults, credentialStore: MenuBarCredentials(), demoSnapshot: .empty)
        let modem = ActiveModem(
            identity: ModemIdentity(kind: .zteMC7530CA, manufacturer: "ZTE", model: "MC7530CA", stableIdentifier: "offline-menu-ca"),
            endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.0.2.1")!, interfaceName: "en9", interfaceIndex: 9),
            capabilities: [.statusRead]
        )
        func commit(_ value: DeviceSnapshot) {
            model.applyReadResult(ModemReadResult(activeModem: modem, snapshot: value,
                                                 reusedActiveEndpoint: true, discoveryReport: nil))
        }
        sample = fixture()
        commit(sample)
        check(model.menuBarText == sample.menuBarText(style: .detailed), "first read fills both rows")
        sample.nrSecondaryCells[0].state = .configured
        commit(sample)
        check(model.menuBarText.primary == "NSA n77 · 2CC", "CA changes publish on the first sample")
        sample.nrSystemMode = .sa
        commit(sample)
        check(model.menuBarText == MenuBarText(primary: "SA n77 · 2CC"), "NSA → SA immediately clears LTE")
        sample.nrSystemMode = .nsa
        commit(sample)
        check(model.menuBarText.secondary == "LTE B7 · 2CC", "SA → NSA immediately restores LTE")
        var updates = 0
        let token = model.objectWillChange.sink { updates += 1 }
        sample.updatedAt = sample.updatedAt.addingTimeInterval(1)
        commit(sample)
        commit(sample)
        check(updates == 0, "unchanged CA and timestamps do not redraw the root")
        withExtendedLifetime(token) {}
        model.menuBarStyle = .compact
        check(model.menuBarText == sample.menuBarText(style: .compact), "style changes update both rows immediately")
        model.menuBarStyle = .iconOnly
        check(model.menuBarText == MenuBarText(primary: ""), "model icon-only stays text-free")
        commit(.empty)
        check(model.menuBarText == MenuBarText(primary: ""), "icon-only stays text-free while connecting")
        model.menuBarStyle = .detailed
        check(model.menuBarText.secondary.isEmpty && !model.menuBarText.primary.contains("CC"),
              "loss of radio data clears both counts and the LTE line")
        return failures
    }

    static func fixture() -> DeviceSnapshot {
        var sample = DeviceSnapshot.empty
        sample.nrSystemMode = .nsa
        sample.nrBand = "n77"
        sample.lteBand = "B7"
        sample.nrPrimaryCell = NRCarrier(role: .primary, band: "n77", nrarfcn: 640608,
                                        bandwidthMHz: 50, physicalCellID: 41, state: .active)
        sample.nrSecondaryCells = [
            NRCarrier(role: .secondary(index: 1), band: "n77", nrarfcn: 633984, bandwidthMHz: 30,
                      physicalCellID: 41, state: .active),
            NRCarrier(role: .secondary(index: 2), band: "n66", nrarfcn: 434910, bandwidthMHz: 20,
                      physicalCellID: 41, state: .active),
            NRCarrier(role: .secondary(index: 3), band: "n71", nrarfcn: 126500, bandwidthMHz: 10,
                      physicalCellID: 41, state: .configured),
            NRCarrier(role: .secondary(index: 4), band: "n66", nrarfcn: 438000, bandwidthMHz: 30,
                      physicalCellID: 41, state: .unknown)
        ]
        sample.ltePrimaryCell = LTECarrier(role: .primary, band: "B7", earfcn: 2850,
                                          bandwidthMHz: 20, physicalCellID: 203, state: .active)
        sample.lteSecondaryCells = [
            LTECarrier(role: .secondary(index: 1), band: "B66", earfcn: 66811, bandwidthMHz: 15,
                       physicalCellID: 203, state: .active),
            LTECarrier(role: .secondary(index: 2), band: "B2", earfcn: 900, bandwidthMHz: 20,
                       physicalCellID: 203, state: .configured)
        ]
        sample.updatedAt = Date(timeIntervalSince1970: 1_000)
        return sample
    }
}

private final class MenuBarCredentials: CredentialStoring {
    func password(for account: String) throws -> String? { nil }
    func setPassword(_ password: String, for account: String) throws {}
    func removePassword(for account: String) throws {}
}
