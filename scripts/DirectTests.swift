import Foundation

@main
enum DirectTests {
    private static let lteBand = "02010031002400020400000000000106000108790084031108000108790084030000120600010805000000"
    private static let signal = "0202004f001c0002040000000000140600b7f394ff2e00170400008000801802000080"
    private static let serving = "02030024004c000204000000000001060001010102010810010001110200010b120a002e01dc000554454c55531503000108011b0100011d040001000000210500000000000024020001002705002e01dc0001"
    private static let noCA = "020400ac004e00020400000000001008000100640000000000110400ff000000120e0000000000ff000000780000000000130a00010064000500000079001401000015010000160400640000001701000018010000"
    private static let nrAndLTE = "0201003100270002040000000000110f00020c0d0180ac090008790084030000120b00020c0d0000000805000000"
    private static let dsdNSA = "02010024001b000204000000000010110001000000000600000000000000000a0000"
    private static let dsdSA = "02010024001b00020400000000001011000100000000060000000000000000120000"
    private static let dsdLTE = "02010024001b00020400000000001011000100000000030000000010000000000000"

    static func main() async {
        var failures: [String] = []

        do {
            let radios = try QMIParser.activeRadios(from: data(lteBand))
            check(radios.count == 1, "LTE RF count", failures: &failures)
            check(radios.first?.band == "B2", "LTE B2", failures: &failures)
            check(radios.first?.channel == 900, "LTE EARFCN", failures: &failures)
            check(radios.first?.bandwidthMHz == 20, "LTE bandwidth", failures: &failures)

            let combined = try QMIParser.activeRadios(from: data(nrAndLTE))
            check(combined.map(\.band) == ["n78", "B2"], "NR/LTE bands", failures: &failures)
            check(combined.map(\.channel) == [633_984, 900], "NR/LTE channels", failures: &failures)
            check(combined.map(\.bandwidthMHz) == [50, 20], "parallel bandwidths", failures: &failures)

            let levels = try QMIParser.signalInfo(from: data(signal))
            check(levels.lteRSRP == -108, "LTE RSRP", failures: &failures)
            check(levels.nrRSRP == nil, "NR sentinel hidden", failures: &failures)

            let network = try QMIParser.servingInfo(from: data(serving))
            check(network.operatorName == "TELUS", "operator", failures: &failures)
            check(network.mcc == "302" && network.mnc == "220", "PLMN", failures: &failures)
            check(try QMIParser.lteSecondaryBands(from: data(noCA)).isEmpty, "inactive CA ignored", failures: &failures)

            check(try QMIParser.systemMode(from: data(dsdNSA)) == .nsa, "explicit NSA", failures: &failures)
            check(try QMIParser.systemMode(from: data(dsdSA)) == .sa, "explicit SA", failures: &failures)
            check(try QMIParser.systemMode(from: data(dsdLTE)) == nil, "LTE is not SA/NSA", failures: &failures)

            let probe = VOSProbeOutput(
                band: data(nrAndLTE),
                signal: data(signal),
                serving: data(serving),
                ca: data(noCA),
                dsd: data(dsdNSA),
                modemVersion: "AT+GMR\r\nRXMG1.20.00.326_0R05\r\nOK\r\n",
                deviceFirmware: "RXMG1.20.00.326.73_0R19"
            )
            let snapshot = try VOSClient.makeSnapshot(
                host: "192.168.225.1",
                interfaceName: "en13",
                probe: probe,
                now: Date(timeIntervalSince1970: 1)
            )
            check(snapshot.detailedMenuTitle == "NSA n78+B2", "menu uses explicit NSA", failures: &failures)
            check(snapshot.modeLabel == "NSA", "mode label", failures: &failures)
            check(snapshot.nrBandwidthMHz == 50 && snapshot.lteBandwidthMHz == 20, "snapshot bandwidth", failures: &failures)
            check(snapshot.moduleVersion?.hasSuffix("_0R05") == true, "modem version", failures: &failures)
            check(snapshot.deviceFirmware == "326.73_0R19", "device firmware", failures: &failures)

            let unknownProbe = VOSProbeOutput(
                band: data(nrAndLTE), signal: nil, serving: nil, ca: nil,
                dsd: nil, modemVersion: nil, deviceFirmware: nil
            )
            let unknown = try VOSClient.makeSnapshot(host: "192.168.225.1", interfaceName: nil, probe: unknownProbe)
            check(unknown.detailedMenuTitle == "NR n78+B2", "does not infer NSA", failures: &failures)
        } catch {
            failures.append("unexpected error: \(error)")
        }

        check(
            DeviceConfiguration(host: "example.com", username: "root", password: "x", refreshInterval: 5).sshHost == nil,
            "rejects public hosts",
            failures: &failures
        )
        checkThrows("truncated QMI", failures: &failures) {
            _ = try QMIParser.activeRadios(from: Data([0x02, 0x01]))
        }

        if ProcessInfo.processInfo.environment["MODEM_SIGNAL_HARDWARE_TEST"] == "1" {
            do {
                let snapshot = try await VOSClient().fetchSnapshot(configuration: DeviceConfiguration(
                    host: "192.168.225.1", username: "root", password: "oelinux123", refreshInterval: 5
                ))
                check(snapshot.hasRadioData, "hardware active band", failures: &failures)
                print("Hardware probe:\n\(snapshot.diagnostics)")
            } catch {
                failures.append("hardware probe: \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            print("All Cellular Modem Monitor tests passed")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }

    private static func data(_ hex: String) -> Data {
        try! QMIParser.data(fromHex: hex)
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ name: String, failures: inout [String]) {
        do {
            if try !condition() { failures.append(name) }
        } catch {
            failures.append("\(name): \(error)")
        }
    }

    private static func checkThrows(_ name: String, failures: inout [String], operation: () throws -> Void) {
        do {
            try operation()
            failures.append(name)
        } catch {}
    }
}
