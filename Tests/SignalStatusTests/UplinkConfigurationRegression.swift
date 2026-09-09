import Foundation
#if canImport(SignalStatus)
@testable import SignalStatus
#endif

enum UplinkConfigurationRegression {
    static func run() -> [String] {
        var failures: [String] = []
        func check(_ value: Bool, _ message: String) {
            if !value { failures.append("UL configuration: \(message)") }
        }
        do {
            // Synthetic values use the layouts from the retail network_info.js,
            // not a comparison of screenshots taken at different times.
            let radio = try parse(
                lteSignals: "-91,-12,18,-70,0,2;-256,-3,16,0,1,1;",
                nrCarriers: "0,41,2,77,633984,30,0,-91,-12,14,-78;1,42,1,71,126500,10,1,-140,-43,-23,-120;"
            )
            check(radio.ltePrimaryCell?.uplinkConfiguration == .enabled
                  && radio.nrPrimaryCell?.uplinkConfiguration == .enabled,
                  "ZTE primary carriers follow the retail page's enabled convention")
            check(radio.lteSecondaryCells.map(\.uplinkConfiguration) == [.disabled, .enabled],
                  "LTE UL flags are not activation states")
            check(radio.nrSecondaryCells.map(\.uplinkConfiguration) == [.disabled, .enabled],
                  "NR UL flags are not activation states")
            check(radio.lteSecondaryCells.map(\.state) == [.active, .configured]
                  && radio.nrSecondaryCells.map(\.state) == [.active, .configured],
                  "activation remains independent")
            check(radio.lteSecondaryCells.last?.signal == .empty
                  && radio.nrSecondaryCells.last?.signal == .empty,
                  "sentinel metrics do not erase UL configuration")

            let now = Date(timeIntervalSince1970: 100)
            let snapshot = radio.snapshot(host: "fixture", interfaceName: nil, now: now)
            check(snapshot.lteSecondaryCells == radio.lteSecondaryCells
                  && snapshot.nrSecondaryCells == radio.nrSecondaryCells,
                  "snapshot retains both radios' UL fields")
            check(snapshot.diagnostics.contains("UL Enabled")
                  && snapshot.diagnostics.contains("UL Disabled"),
                  "copied diagnostics include UL configuration")
            var updated = snapshot
            updated.nrSecondaryCells[0].uplinkConfiguration = .enabled
            check(updated != snapshot, "UL-only NR updates are observable")
            updated = snapshot
            updated.lteSecondaryCells[0].uplinkConfiguration = .enabled
            check(updated != snapshot, "UL-only LTE updates are observable")

            let values: [(String, RadioUplinkConfiguration)] = [
                ("1", .enabled), ("0", .disabled), (" 1 ", .enabled),
                ("", .unknown), ("2", .unknown), ("-1", .unknown),
                ("true", .unknown), ("garbage", .unknown), ("255", .unknown)
            ]
            for (raw, expected) in values {
                let parsed = try parse(
                    lteSignals: "-91,-12,18,-70,\(raw),2;",
                    nrCarriers: "0,41,2,77,633984,30,\(raw),-91,-12,14,-78;"
                )
                check(parsed.lteSecondaryCells.first?.uplinkConfiguration == expected,
                      "LTE flag '\(raw)' → \(expected)")
                check(parsed.nrSecondaryCells.first?.uplinkConfiguration == expected,
                      "NR flag '\(raw)' → \(expected)")
            }

            let truncated = try parse(lteSignals: "-91,-12,18,-70,1;", nrCarriers: "0,41,2,77,633984,30;")
            check(truncated.lteSecondaryCells.first?.uplinkConfiguration == .enabled
                  && truncated.lteSecondaryCells.first?.state == .unknown,
                  "LTE UL survives a missing independent state column")
            check(truncated.lteSecondaryCells.last?.uplinkConfiguration == .unknown
                  && truncated.nrSecondaryCells.first?.uplinkConfiguration == .unknown,
                  "missing fields and missing records are unknown")

            let emptySlot = try parse(lteSignals: ";-91,-12,18,-70,1,2;", nrCarriers: nil)
            check(emptySlot.lteSecondaryCells.map(\.uplinkConfiguration) == [.unknown, .enabled],
                  "an empty LTE signal slot does not shift the next carrier's flag")
            let emptyCarrier = try parse(
                lteSignals: "-91,-12,18,-70,0,2;-91,-12,18,-70,1,2;",
                nrCarriers: nil, lteCarriers: "203,7,0,2850,20;;203,66,1,66811,15;"
            )
            check(emptyCarrier.lteSecondaryCells.map(\.uplinkConfiguration) == [.enabled],
                  "an empty LTE identity slot does not shift UL flags")
            let missing = try parse(lteSignals: nil, nrCarriers: nil)
            check(missing.lteSecondaryCells.allSatisfy { $0.uplinkConfiguration == .unknown },
                  "a missing ltecasig is not disabled")
            check(missing.snapshot(host: "fixture", interfaceName: nil).diagnostics.contains("UL Unknown"),
                  "unknown is explicit in diagnostics")
            let noNR = try parse(
                lteSignals: nil, nrCarriers: "0,41,2,77,633984,30,1;", hasNR: false
            )
            check(noNR.nrPrimaryCell == nil && noNR.nrSecondaryCells.isEmpty,
                  "stale NR UL is not displayed without a valid primary carrier")

            let unmappedLTE = LTECarrier(role: .primary, band: "B7", earfcn: 2850,
                                         bandwidthMHz: 20, physicalCellID: 203, state: .active)
            let unmappedNR = NRCarrier(role: .primary, band: "n77", nrarfcn: 640608,
                                       bandwidthMHz: 50, physicalCellID: 41, state: .active)
            check(unmappedLTE.uplinkConfiguration == .unknown
                  && unmappedNR.uplinkConfiguration == .unknown,
                  "other backends do not infer UL from a primary or active role")
            check(RadioUplinkConfiguration.enabled.localizedLabel(language: .english) == "UL Enabled"
                  && RadioUplinkConfiguration.enabled.localizedLabel(language: .simplifiedChinese) == "上行启用"
                  && RadioUplinkConfiguration.disabled.localizedLabel(language: .simplifiedChinese) == "上行禁用"
                  && RadioUplinkConfiguration.unknown.localizedLabel(language: .simplifiedChinese) == "上行未知",
                  "English and Chinese labels")
        } catch {
            failures.append("UL configuration fixtures: \(error)")
        }
        return failures
    }

    private static func parse(
        lteSignals: String?, nrCarriers: String?,
        lteCarriers: String = "203,7,0,2850,20;203,2,1,900,20;203,66,1,66811,15;",
        hasNR: Bool = true
    ) throws -> MC7530RadioInfo {
        var object: [String: Any] = [
            "network_type": hasNR ? "ENDC" : "LTE",
            "wan_active_band": "B7", "wan_active_channel": 2850, "lte_pci": 203,
            "lteca": lteCarriers
        ]
        object["ltecasig"] = lteSignals
        object["nrca"] = nrCarriers
        if hasNR {
            object["nr5g_action_band"] = "n77"
            object["nr5g_action_channel"] = 640608
            object["nr5g_bandwidth"] = 50
            object["nr5g_pci"] = 41
        }
        return try MC7530Parser.parse(data: JSONSerialization.data(withJSONObject: object))
    }
}
