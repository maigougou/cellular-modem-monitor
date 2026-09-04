import Darwin
import Foundation

enum VOSClientError: LocalizedError, Equatable, ModemFailureCategorizing {
    case invalidHost
    case unreachable
    case authenticationFailed
    case sshUnavailable
    case askPassUnavailable
    case timedOut
    case qmiUnavailable(String?)
    case invalidPLMN
    case commandFailed(String)
    case verificationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Enter a private or local device address."
        case .unreachable:
            return "The cellular modem is not reachable over SSH."
        case .authenticationFailed:
            return "The modem SSH username or password was rejected."
        case .sshUnavailable:
            return "macOS OpenSSH is not available."
        case .askPassUnavailable:
            return "The app's SSH password helper is missing. Reinstall the app."
        case .timedOut:
            return "The modem operation timed out."
        case let .qmiUnavailable(message):
            return message.map { "Modem QMI is unavailable: \($0)" } ?? "Modem QMI is unavailable."
        case .invalidPLMN:
            return "The selected network does not contain a valid five- or six-digit PLMN."
        case let .commandFailed(message):
            return message
        case let .verificationFailed(message):
            return message
        case .invalidResponse:
            return "The modem SSH/QMI probe returned an unreadable response."
        }
    }

    var modemFailureCategory: ModemFailureCategory {
        switch self {
        case .authenticationFailed:
            return .authentication
        case .qmiUnavailable:
            return .qmiUnavailable
        default:
            return .other
        }
    }
}

actor VOSClient {
    private let executor: SystemSSHExecutor
    private var plmnNameCache: [String: String] = [:]

    init(executor: SystemSSHExecutor = SystemSSHExecutor()) {
        self.executor = executor
    }

    func fetchSnapshot(configuration: DeviceConfiguration) async throws -> DeviceSnapshot {
        guard let host = configuration.sshHost else { throw VOSClientError.invalidHost }
        let sourceAddress = configuration.sourceAddress
            ?? (host == "192.168.225.1" ? LocalInterface.vosSourceAddress() : nil)
        let output = try await executor.run(
            host: host,
            username: configuration.username,
            password: configuration.password,
            sourceAddress: sourceAddress,
            script: Self.readOnlyProbe
        )
        let probe = try VOSProbeOutput.parse(output)
        var snapshot = try Self.makeSnapshot(
            host: host,
            interfaceName: configuration.interfaceName ?? LocalInterface.vosInterfaceName(),
            probe: probe
        )
        if snapshot.operatorName == nil,
           let mcc = snapshot.mcc,
           let mnc = snapshot.mnc {
            let plmn = mcc + mnc
            if let cached = plmnNameCache[plmn] {
                snapshot.operatorName = cached
            } else if let mccValue = UInt16(mcc),
                      let mncValue = UInt16(mnc),
                      let response = try? await runQMI(
                          QMIParser.getPLMNNameRequest(
                              mcc: mccValue,
                              mnc: mncValue,
                              mncHasThreeDigits: mnc.count == 3
                          ),
                          configuration: configuration,
                          timeout: 12
                      ),
                      let parsedName = try? QMIParser.plmnName(from: response),
                      let name = parsedName.displayName {
                plmnNameCache[plmn] = name
                snapshot.operatorName = name
            }
        }
        return snapshot
    }

    func fetchDeviceFingerprint(configuration: DeviceConfiguration) async throws -> String {
        guard let host = configuration.sshHost else { throw VOSClientError.invalidHost }
        let sourceAddress = configuration.sourceAddress
            ?? (host == "192.168.225.1" ? LocalInterface.vosSourceAddress() : nil)
        let output = try await executor.run(
            host: host,
            username: configuration.username,
            password: configuration.password,
            sourceAddress: sourceAddress,
            script: Self.deviceIdentityProbe
        )
        guard let fingerprint = try HexFields.parse(output)["DEVICE_ID"],
              fingerprint.count == 64,
              fingerprint.allSatisfy({ $0.isHexDigit })
        else { throw VOSClientError.invalidResponse }
        return fingerprint.lowercased()
    }

    func fetchOperatorSelection(configuration: DeviceConfiguration) async throws -> OperatorSelection {
        let output = try await runAT("AT+COPS?", configuration: configuration, timeout: 18)
        return try ATCOPSParser.selection(from: output)
    }

    func scanNetworks(configuration: DeviceConfiguration) async throws -> [CellularNetwork] {
        let output = try await runAT("AT+COPS=?", configuration: configuration, timeout: 155)
        try ATCOPSParser.requireOK(output)
        let networks = try ATCOPSParser.networks(from: output)
        guard !networks.isEmpty else {
            throw VOSClientError.commandFailed("The modem completed its scan but returned no cellular networks.")
        }
        return networks
    }

    func selectNetwork(
        plmn: String,
        configuration: DeviceConfiguration
    ) async throws -> OperatorSelection {
        try Task.checkCancellation()
        guard (plmn.count == 5 || plmn.count == 6), plmn.allSatisfy(\.isNumber) else {
            throw VOSClientError.invalidPLMN
        }

        var commandFailure: Error?
        do {
            let output = try await runAT(
                "AT+COPS=1,2,\"\(plmn)\"",
                configuration: configuration,
                timeout: 95
            )
            try ATCOPSParser.requireOK(output)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            commandFailure = error
        }

        for attempt in 0..<5 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
            do {
                let selection = try await fetchOperatorSelection(configuration: configuration)
                if selection.mode == .manual, selection.plmn == plmn {
                    return selection
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A transient read failure is retried below; cancellation is
                // deliberately never converted into an ordinary retry.
            }
        }

        let reason = commandFailure.map { " (\($0.localizedDescription))" } ?? ""
        throw VOSClientError.verificationFailed(
            "The modem did not verify registration on PLMN \(plmn)\(reason)."
        )
    }

    func selectAutomaticNetwork(configuration: DeviceConfiguration) async throws -> OperatorSelection {
        try Task.checkCancellation()
        var commandFailure: Error?
        do {
            let output = try await runAT("AT+COPS=0", configuration: configuration, timeout: 95)
            try ATCOPSParser.requireOK(output)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            commandFailure = error
        }

        for attempt in 0..<5 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
            do {
                let selection = try await fetchOperatorSelection(configuration: configuration)
                if selection.mode == .automatic {
                    return selection
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve the existing retry behavior for transport errors.
            }
        }
        if let commandFailure {
            throw VOSClientError.verificationFailed(
                "Automatic network selection could not be verified after the command failed (\(commandFailure.localizedDescription)); operator-selection state is unknown."
            )
        }
        throw VOSClientError.verificationFailed(
            "The modem accepted automatic network selection but did not confirm it; operator-selection state is unknown."
        )
    }

    func fetchNRSystemSelectionPreferences(
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences {
        let response = try await runQMI(
            QMIParser.getSystemSelectionRequest(),
            configuration: configuration,
            timeout: 12
        )
        return try QMIParser.systemSelectionPreferences(from: response)
    }

    func setNRSystemSelectionPreferences(
        modePreference: UInt16,
        saBands: NRBandMask,
        nsaBands: NRBandMask,
        lteBands: LTEBandMask? = nil,
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences {
        let request = QMIParser.setNRSystemSelectionRequest(
            modePreference: modePreference,
            saBands: saBands,
            nsaBands: nsaBands,
            lteBands: lteBands
        )
        let response = try await runQMI(request, configuration: configuration, timeout: 18)
        do {
            try QMIParser.validateSetSystemSelectionResponse(response)
        } catch QMIParserError.requestFailed(26) {
            // Qualcomm may return NoEffect when the requested tuple is already
            // active. Exact read-back below is still authoritative.
        } catch {
            throw error
        }

        var lastReadBack: NRSystemSelectionPreferences?
        for attempt in 0..<5 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 750_000_000)
            }
            do {
                let verified = try await fetchNRSystemSelectionPreferences(configuration: configuration)
                lastReadBack = verified
                if verified.modePreference == modePreference,
                   verified.saBands == saBands,
                   verified.nsaBands == nsaBands,
                   lteBands == nil || verified.lteBands == lteBands {
                    return verified
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A transient read failure is retried; cancellation is not.
            }
        }
        let suffix = lastReadBack == nil ? " No readable preference response was returned." : ""
        throw VOSClientError.verificationFailed(
            "The modem accepted the radio-access request but its mode and band-mask read-back did not match.\(suffix)"
        )
    }

    private func runAT(
        _ command: String,
        configuration: DeviceConfiguration,
        timeout: TimeInterval
    ) async throws -> String {
        try Task.checkCancellation()
        guard let host = configuration.sshHost else { throw VOSClientError.invalidHost }
        let sourceAddress = configuration.sourceAddress
            ?? (host == "192.168.225.1" ? LocalInterface.vosSourceAddress() : nil)
        let output = try await executor.run(
            host: host,
            username: configuration.username,
            password: configuration.password,
            sourceAddress: sourceAddress,
            script: Self.atProbe(command: command, alarm: Int(ceil(timeout - 3))),
            timeout: timeout
        )
        guard let encoded = try HexFields.parse(output)["AT_HEX"],
              let data = try? QMIParser.data(fromHex: encoded),
              let value = String(data: data, encoding: .utf8)
        else { throw VOSClientError.invalidResponse }
        return value
    }

    private func runQMI(
        _ request: Data,
        configuration: DeviceConfiguration,
        timeout: TimeInterval
    ) async throws -> Data {
        try Task.checkCancellation()
        guard let host = configuration.sshHost else { throw VOSClientError.invalidHost }
        let sourceAddress = configuration.sourceAddress
            ?? (host == "192.168.225.1" ? LocalInterface.vosSourceAddress() : nil)
        let output = try await executor.run(
            host: host,
            username: configuration.username,
            password: configuration.password,
            sourceAddress: sourceAddress,
            script: Self.qmiProbe(request: request, alarm: Int(ceil(timeout - 3))),
            timeout: timeout
        )
        guard let encoded = try HexFields.parse(output)["QMI_HEX"] else {
            throw VOSClientError.invalidResponse
        }
        return try QMIParser.data(fromHex: encoded)
    }

    static func makeSnapshot(
        host: String,
        interfaceName: String?,
        probe: VOSProbeOutput,
        now: Date = Date()
    ) throws -> DeviceSnapshot {
        let radios: [QMIRadioReading]
        do {
            radios = try QMIParser.activeRadios(from: probe.band)
        } catch QMIParserError.noActiveBand {
            // A valid NAS response without a serving band is normal while the
            // single SIM slot is empty or a newly inserted SIM is registering.
            // Preserve it as a reachable no-service snapshot so stale carrier
            // and radio data can be cleared without misreporting a QMI fault.
            radios = []
        } catch {
            throw VOSClientError.qmiUnavailable(error.localizedDescription)
        }

        if radios.isEmpty {
            return DeviceSnapshot(
                host: host,
                interfaceName: interfaceName,
                operatorName: nil,
                mcc: nil,
                mnc: nil,
                nrSystemMode: nil,
                nrBand: nil,
                nrChannel: nil,
                nrBandwidthMHz: nil,
                nrRaw: nil,
                nrSignal: .empty,
                lteBand: nil,
                lteChannel: nil,
                lteBandwidthMHz: nil,
                lteRaw: nil,
                lteSignal: .empty,
                ltePrimaryCell: nil,
                lteSecondaryCells: [],
                moduleVersion: cleanModemVersion(probe.modemVersion),
                deviceFirmware: cleanVOSVersion(probe.deviceFirmware),
                updatedAt: now
            )
        }

        var seenNRCarriers = Set<String>()
        let nrReadings = radios.filter { reading in
            guard reading.kind == .nr else { return false }
            return seenNRCarriers.insert("\(reading.band)-\(reading.channel)").inserted
        }
        let lteReadings = radios.filter { $0.kind == .lte }
        let signal = probe.signal.flatMap { try? QMIParser.signalInfo(from: $0) }
        let serving = probe.serving.flatMap { try? QMIParser.servingInfo(from: $0) }
        let location = probe.location.flatMap { try? QMIParser.cellLocationInfo(from: $0) }
        let nr = location?.nrARFCN.flatMap { servingARFCN in
            nrReadings.first { $0.channel == servingARFCN }
        } ?? nrReadings.first
        let nrSecondaryReadings = nrReadings.filter { reading in
            guard let nr else { return false }
            return reading.band != nr.band || reading.channel != nr.channel
        }
        let lte = lteReadings.first
        let explicitMode: NRSystemMode? = {
            guard nr != nil, let dsd = probe.dsd else { return nil }
            return try? QMIParser.systemMode(from: dsd)
        }()

        let carrierAggregation = probe.ca.flatMap { try? QMIParser.lteCarrierAggregation(from: $0) }
        let nrLocationSignal = location?.nr.map { Self.makeRadioSignal($0.signal) }
        let lteLocationSignal = location?.lte?.servingCellMeasurement.map { Self.makeRadioSignal($0.signal) }
        let nrSignal = RadioSignal(
            rsrpDBm: signal?.nrRSRP ?? nrLocationSignal?.rsrpDBm,
            rsrqDB: signal?.nrRSRQ.map(Double.init) ?? nrLocationSignal?.rsrqDB,
            rssiDBm: nrLocationSignal?.rssiDBm,
            snrDB: signal?.nrSNR ?? nrLocationSignal?.snrDB
        )
        let nrPrimaryCell = nr.map {
            NRCarrier(
                role: .primary,
                band: $0.band,
                nrarfcn: $0.channel,
                bandwidthMHz: $0.bandwidthMHz,
                physicalCellID: location?.nr?.physicalCellID,
                state: .active,
                globalCellID: location?.nr?.globalCellID,
                signal: nrSignal
            )
        }
        let nrSecondaryCells = nrSecondaryReadings.enumerated().map { index, reading in
            NRCarrier(
                role: .secondary(index: index + 1),
                band: reading.band,
                nrarfcn: reading.channel,
                bandwidthMHz: reading.bandwidthMHz,
                physicalCellID: nil,
                state: .active
            )
        }
        let lteSignal = RadioSignal(
            rsrpDBm: signal?.lteRSRP ?? lteLocationSignal?.rsrpDBm,
            rsrqDB: signal?.lteRSRQ.map(Double.init) ?? lteLocationSignal?.rsrqDB,
            rssiDBm: signal?.lteRSSI ?? lteLocationSignal?.rssiDBm,
            snrDB: signal?.lteSNR ?? lteLocationSignal?.snrDB
        )
        let ltePrimaryCell = carrierAggregation?.primaryCell.map {
            Self.makeCarrier($0, location: location, primarySignal: lteSignal)
        }
        let lteSecondaryCells = carrierAggregation?.secondaryCells
            .filter { $0.state != .deconfigured }
            .map { Self.makeCarrier($0, location: location, primarySignal: nil) } ?? []
        let allCACarriers = [carrierAggregation?.primaryCell].compactMap { $0 } +
            (carrierAggregation?.secondaryCells ?? [])
        func matchedBand(earfcn: UInt32, pci: UInt16) -> String? {
            allCACarriers.first { $0.earfcn == earfcn && $0.physicalCellID == pci }?.band
        }
        var lteNeighbors: [LTECellNeighbor] = []
        if let lteLocation = location?.lte {
            lteNeighbors.append(contentsOf: lteLocation.cells
                .filter { $0.physicalCellID != lteLocation.physicalCellID }
                .map { measurement in
                    LTECellNeighbor(
                        band: matchedBand(earfcn: lteLocation.earfcn, pci: measurement.physicalCellID) ?? lte?.band,
                        earfcn: lteLocation.earfcn,
                        physicalCellID: measurement.physicalCellID,
                        signal: Self.makeRadioSignal(measurement.signal)
                    )
                })
        }
        for frequency in location?.lteInterfrequency ?? [] {
            lteNeighbors.append(contentsOf: frequency.cells.map { measurement in
                LTECellNeighbor(
                    band: matchedBand(earfcn: frequency.earfcn, pci: measurement.physicalCellID),
                    earfcn: frequency.earfcn,
                    physicalCellID: measurement.physicalCellID,
                    signal: Self.makeRadioSignal(measurement.signal)
                )
            })
        }

        return DeviceSnapshot(
            host: host,
            interfaceName: interfaceName,
            operatorName: serving?.operatorName,
            mcc: serving?.mcc,
            mnc: serving?.mnc,
            nrSystemMode: explicitMode,
            nrBand: nr?.band,
            nrChannel: nr.map { String($0.channel) },
            nrBandwidthMHz: nr?.bandwidthMHz,
            nrRaw: nr?.rawDescription,
            nrSignal: nrSignal,
            nrGlobalCellID: location?.nr?.globalCellID,
            nrPhysicalCellID: location?.nr?.physicalCellID,
            nrPrimaryCell: nrPrimaryCell,
            nrSecondaryCells: nrSecondaryCells,
            lteBand: lte?.band,
            lteChannel: lte.map { String($0.channel) },
            lteBandwidthMHz: lte?.bandwidthMHz,
            lteRaw: lte?.rawDescription,
            lteSignal: lteSignal,
            lteGlobalCellID: location?.lte.map { UInt64($0.globalCellID) },
            ltePhysicalCellID: location?.lte?.physicalCellID,
            ltePrimaryCell: ltePrimaryCell,
            lteSecondaryCells: lteSecondaryCells,
            lteNeighborCells: lteNeighbors,
            moduleVersion: cleanModemVersion(probe.modemVersion),
            deviceFirmware: cleanVOSVersion(probe.deviceFirmware),
            updatedAt: now
        )
    }

    private static func makeCarrier(
        _ carrier: QMILTECarrier,
        location: QMICellLocationInfo?,
        primarySignal: RadioSignal?
    ) -> LTECarrier {
        let role: RadioCarrierRole
        switch carrier.role {
        case .primary:
            role = .primary
        case .secondary:
            role = .secondary(index: carrier.index.map(Int.init))
        }

        let state: RadioCarrierState?
        switch carrier.state {
        case .none:
            state = nil
        case .some(.configuredActivated):
            state = .active
        case .some(.configuredDeactivated):
            state = .configured
        case .some(.deconfigured):
            state = .deconfigured
        case .some(.unknown):
            state = .unknown
        }

        let exactMeasurement: QMILTECellMeasurement? = {
            if let intra = location?.lte, intra.earfcn == carrier.earfcn,
               let cell = intra.cells.first(where: { $0.physicalCellID == carrier.physicalCellID }) {
                return cell
            }
            return location?.lteInterfrequency
                .first { $0.earfcn == carrier.earfcn }?
                .cells.first { $0.physicalCellID == carrier.physicalCellID }
        }()
        let isServingCell = location?.lte?.earfcn == carrier.earfcn &&
            location?.lte?.physicalCellID == carrier.physicalCellID
        let carrierSignal: RadioSignal = {
            if isServingCell {
                return primarySignal ?? exactMeasurement.map { Self.makeRadioSignal($0.signal) } ?? .empty
            }
            if location == nil {
                // Older firmware may not return cell-location information. In
                // that case the RAT-level signal is still the best available
                // PCell value.
                return primarySignal ?? exactMeasurement.map { Self.makeRadioSignal($0.signal) } ?? .empty
            }
            // A handover can occur between the signal, CA and location QMI
            // requests. Never attach the new serving signal to a stale PCell.
            return exactMeasurement.map { Self.makeRadioSignal($0.signal) } ?? .empty
        }()

        return LTECarrier(
            role: role,
            band: carrier.band,
            earfcn: carrier.earfcn,
            bandwidthMHz: carrier.bandwidthMHz,
            physicalCellID: carrier.physicalCellID,
            state: state,
            globalCellID: isServingCell ? location?.lte.map { UInt64($0.globalCellID) } : nil,
            signal: carrierSignal
        )
    }

    private static func makeRadioSignal(_ signal: QMICellSignalMetrics) -> RadioSignal {
        RadioSignal(
            rsrpDBm: signal.rsrpDBm.map { Int($0.rounded()) },
            rsrqDB: signal.rsrqDB,
            rssiDBm: signal.rssiDBm.map { Int($0.rounded()) },
            snrDB: signal.snrDB
        )
    }

    private static func cleanModemVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        return value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.contains("_0R") }
    }

    private static func cleanVOSVersion(_ value: String?) -> String? {
        guard let value = BandParser.clean(value) else { return nil }
        let pattern = #"(?:^|\.)(\d+\.\d+_0R\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value)
        else { return value }
        return String(value[range])
    }

    private static func atProbe(command: String, alarm: Int) -> String {
        let commandHex = Data(command.utf8).map { String(format: "%02x", $0) }.joined()
        let safeAlarm = max(3, min(alarm, 180))
        return #"""
use strict;
use warnings;

$| = 1;
my $at_pid;
my $stop_at = sub {
    return unless defined($at_pid) && $at_pid > 0;
    kill "TERM", $at_pid;
    kill "KILL", $at_pid;
    waitpid($at_pid, 0);
    undef $at_pid;
};
$SIG{ALRM} = sub { $stop_at->(); die "AT command timeout\n" };
$SIG{HUP} = sub { $stop_at->(); exit 1 };
$SIG{TERM} = sub { $stop_at->(); exit 1 };
alarm \#(safeAlarm);

my $command = pack("H*", "\#(commandHex)");
$at_pid = open(my $at, "-|", "/usr/bin/atcli", $command);
die "atcli unavailable\n" unless defined($at_pid);
local $/;
my $value = <$at> // "";
close($at);
undef $at_pid;
print "AT_HEX=", unpack("H*", $value), "\n";

alarm 0;
"""#
    }

    private static func qmiProbe(request: Data, alarm: Int) -> String {
        let requestHex = request.map { String(format: "%02x", $0) }.joined()
        let safeAlarm = max(3, min(alarm, 60))
        return #"""
use strict;
use warnings;
use Socket;

$| = 1;
$SIG{ALRM} = sub { die "QMI control timeout\n" };
alarm \#(safeAlarm);

my ($node, $port);
open(my $lookup, "-|", "/usr/bin/qrtr-lookup")
    or die "qrtr-lookup unavailable\n";
while (my $line = <$lookup>) {
    if ($line =~ /^\s*3\s+\S+\s+\S+\s+(\d+)\s+(\d+)/) {
        ($node, $port) = ($1, $2);
        last;
    }
}
close($lookup);
die "NAS QRTR service unavailable\n" unless defined($node) && defined($port);

socket(my $socket, 42, 2, 0) or die "QRTR socket failed\n";
connect($socket, pack("SxxLL", 42, $node, $port))
    or die "QRTR connect failed\n";
my $request = pack("H*", "\#(requestHex)");
my (undef, $expected_transaction, $expected_message) = unpack("Cvv", $request);
defined(send($socket, $request, 0)) or die "QMI send failed\n";
my $response;
while (1) {
    defined(recv($socket, $response, 16384, 0))
        or die "QMI receive failed\n";
    next unless length($response) >= 7;
    my ($flags, $transaction, $message) = unpack("Cvv", $response);
    last if $flags == 2 &&
            $transaction == $expected_transaction &&
            $message == $expected_message;
}
close($socket);
print "QMI_HEX=", unpack("H*", $response), "\n";

alarm 0;
"""#
    }

    // Hash the USB gadget serial on VOS itself. Only the digest leaves the
    // device; it binds an in-memory radio baseline to one physical modem even
    // when multiple units share 192.168.225.1.
    private static let deviceIdentityProbe = #"""
use strict;
use warnings;

my @paths = (
    "/sys/kernel/config/usb_gadget/g1/strings/0x409/serialnumber",
    "/sys/class/android_usb/android0/iSerial"
);
for my $path (@paths) {
    next unless -r $path && -s $path;
    open(my $hash, "-|", "/usr/bin/sha256sum", $path)
        or next;
    my $line = <$hash> // "";
    close($hash);
    if ($line =~ /^([0-9a-fA-F]{64})\b/) {
        print "DEVICE_ID=", lc($1), "\n";
        exit 0;
    }
}
die "stable device identity unavailable\n";
"""#

    // Sent to `/usr/bin/perl -` through SSH stdin. It performs read-only QMI
    // requests and leaves no file, process or setting behind on the modem.
    static let readOnlyProbe = #"""
use strict;
use warnings;
use Socket;

$| = 1;
$SIG{ALRM} = sub { die "QMI probe timeout\n" };
alarm 6;

sub endpoints {
    my %found;
    open(my $lookup, "-|", "/usr/bin/qrtr-lookup")
        or die "qrtr-lookup unavailable\n";
    while (my $line = <$lookup>) {
        if ($line =~ /^\s*(\d+)\s+\S+\s+\S+\s+(\d+)\s+(\d+)/) {
            $found{$1} ||= [$2, $3];
        }
    }
    close($lookup);
    return %found;
}

sub qmi {
    my ($endpoint, $transaction, $message) = @_;
    socket(my $socket, 42, 2, 0) or die "QRTR socket failed\n";
    connect($socket, pack("SxxLL", 42, $endpoint->[0], $endpoint->[1]))
        or die "QRTR connect failed\n";
    my $request = pack("Cvvv", 0, $transaction, $message, 0);
    defined(send($socket, $request, 0)) or die "QMI send failed\n";
    defined(recv($socket, my $response, 8192, 0))
        or die "QMI receive failed\n";
    close($socket);
    return $response;
}

sub optional_qmi {
    my ($endpoint, $transaction, $message) = @_;
    my $value = eval { qmi($endpoint, $transaction, $message) };
    return defined($value) ? $value : "";
}

sub read_file {
    my ($path) = @_;
    return "" unless open(my $file, "<", $path);
    local $/;
    my $value = <$file> // "";
    close($file);
    $value =~ s/[\r\n]+$//;
    return $value;
}

sub modem_version {
    return "" unless open(my $at, "-|", "/usr/bin/atcli", "AT+GMR");
    local $/;
    my $value = <$at> // "";
    close($at);
    return $value;
}

sub emit_hex {
    my ($name, $value) = @_;
    print $name, "=", unpack("H*", $value // ""), "\n";
}

my %endpoint = endpoints();
die "NAS QRTR service unavailable\n" unless $endpoint{3};
my $band = qmi($endpoint{3}, 1, 0x0031);

print "MODEM_SIGNAL_QMI_V1\n";
emit_hex("BAND_HEX", $band);
emit_hex("SIGNAL_HEX", optional_qmi($endpoint{3}, 2, 0x004f));
emit_hex("SERVING_HEX", optional_qmi($endpoint{3}, 3, 0x0024));
emit_hex("CA_HEX", optional_qmi($endpoint{3}, 4, 0x00ac));
emit_hex("LOCATION_HEX", optional_qmi($endpoint{3}, 5, 0x0043));
emit_hex("DSD_HEX", $endpoint{42} ? optional_qmi($endpoint{42}, 1, 0x0024) : "");
emit_hex("MODEM_HEX", modem_version());
emit_hex("DEVICE_HEX", read_file("/oem/cei_module_ver_vos_id"));

alarm 0;
"""#
}

enum ATCOPSParser {
    static func requireOK(_ output: String) throws {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.contains("OK"),
              !lines.contains(where: {
                  $0 == "ERROR" || $0.hasPrefix("+CME ERROR") || $0.hasPrefix("+CMS ERROR")
              })
        else {
            let reason = lines.first(where: {
                $0 == "ERROR" || $0.hasPrefix("+CME ERROR") || $0.hasPrefix("+CMS ERROR")
            }) ?? "No OK response"
            throw VOSClientError.commandFailed("The modem rejected the network command: \(reason).")
        }
    }

    static func selection(from output: String) throws -> OperatorSelection {
        try requireOK(output)
        guard let payload = output.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("+COPS:") && !$0.dropFirst(6).trimmingCharacters(in: .whitespaces).hasPrefix("(") })?
            .dropFirst(6)
        else { throw VOSClientError.invalidResponse }

        let fields = splitCSV(String(payload))
        guard let rawMode = fields.first.flatMap(Int.init),
              let mode = OperatorSelectionMode(rawValue: rawMode)
        else { throw VOSClientError.invalidResponse }

        let format = fields.count > 1 ? Int(fields[1]) : nil
        let operatorValue = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
        let eons = fields.count > 4 && !fields[3].isEmpty ? fields[3] : nil
        let operatorName = eons ?? (format == 2 ? nil : operatorValue)
        let plmn = format == 2 && operatorValue.map(isPLMN) == true ? operatorValue : nil
        let accessTechnology = fields.count > 3
            ? fields.reversed().compactMap { Int($0) }.first.flatMap(CellularAccessTechnology.init(rawValue:))
            : nil
        return OperatorSelection(
            mode: mode,
            operatorName: operatorName,
            plmn: plmn,
            accessTechnology: accessTechnology
        )
    }

    static func networks(from output: String) throws -> [CellularNetwork] {
        try requireOK(output)
        var grouped: [String: CellularNetwork] = [:]

        for tuple in tuples(in: output) {
            let fields = splitCSV(tuple)
            guard fields.count >= 4,
                  let statusRaw = Int(fields[0]),
                  let availability = NetworkAvailability(rawValue: statusRaw),
                  isPLMN(fields[3])
            else { continue }
            let longName = fields[1]
            let shortName = fields[2]
            let plmn = fields[3]
            let access = fields.count > 4
                ? Int(fields[4]).flatMap(CellularAccessTechnology.init(rawValue:))
                : nil

            if var existing = grouped[plmn] {
                if availability.mergePriority > existing.availability.mergePriority {
                    existing.availability = availability
                }
                if existing.longName.isEmpty { existing.longName = longName }
                if existing.shortName.isEmpty { existing.shortName = shortName }
                if let access, !existing.accessTechnologies.contains(access) {
                    existing.accessTechnologies.append(access)
                    existing.accessTechnologies.sort { $0.rawValue < $1.rawValue }
                }
                grouped[plmn] = existing
            } else {
                grouped[plmn] = CellularNetwork(
                    longName: longName,
                    shortName: shortName,
                    plmn: plmn,
                    availability: availability,
                    accessTechnologies: access.map { [$0] } ?? []
                )
            }
        }

        return grouped.values.sorted {
            if $0.availability.sortOrder != $1.availability.sortOrder {
                return $0.availability.sortOrder < $1.availability.sortOrder
            }
            let nameComparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
            return $0.plmn < $1.plmn
        }
    }

    private static func splitCSV(_ value: String) -> [String] {
        var result: [String] = []
        var field = ""
        var quoted = false
        var escaped = false
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if escaped {
                field.append(character)
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                result.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        result.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static func tuples(in output: String) -> [String] {
        var result: [String] = []
        var value = ""
        var depth = 0
        var quoted = false
        var escaped = false
        let characters = Array(output)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if escaped {
                if depth > 0 { value.append(character) }
                escaped = false
            } else if character == "\\", quoted {
                if depth > 0 { value.append(character) }
                escaped = true
            } else if character == "\"" {
                if depth > 0 { value.append(character) }
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    if depth > 0 { value.append(characters[index + 1]) }
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if !quoted, character == "(" {
                if depth == 0 { value = "" } else { value.append(character) }
                depth += 1
            } else if !quoted, character == ")", depth > 0 {
                depth -= 1
                if depth == 0 {
                    result.append(value)
                    value = ""
                } else {
                    value.append(character)
                }
            } else if depth > 0 {
                value.append(character)
            }
            index += 1
        }
        return result
    }

    private static func isPLMN(_ value: String) -> Bool {
        (value.count == 5 || value.count == 6) && value.allSatisfy(\.isNumber)
    }

}

private enum HexFields {
    static func parse(_ data: Data) throws -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VOSClientError.invalidResponse
        }
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \Character.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            result[key] = value
        }
        return result
    }
}

struct VOSProbeOutput: Equatable, Sendable {
    let band: Data
    let signal: Data?
    let serving: Data?
    let ca: Data?
    var location: Data? = nil
    let dsd: Data?
    let modemVersion: String?
    let deviceFirmware: String?

    static func parse(_ data: Data) throws -> VOSProbeOutput {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VOSClientError.invalidResponse
        }
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard lines.first == "MODEM_SIGNAL_QMI_V1" else { throw VOSClientError.invalidResponse }

        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        guard let bandHex = fields["BAND_HEX"] else { throw VOSClientError.invalidResponse }

        do {
            return VOSProbeOutput(
                band: try QMIParser.data(fromHex: bandHex),
                signal: try optionalData(fields["SIGNAL_HEX"]),
                serving: try optionalData(fields["SERVING_HEX"]),
                ca: try optionalData(fields["CA_HEX"]),
                location: try optionalData(fields["LOCATION_HEX"]),
                dsd: try optionalData(fields["DSD_HEX"]),
                modemVersion: try optionalText(fields["MODEM_HEX"]),
                deviceFirmware: try optionalText(fields["DEVICE_HEX"])
            )
        } catch {
            throw VOSClientError.invalidResponse
        }
    }

    private static func optionalData(_ hex: String?) throws -> Data? {
        guard let hex, !hex.isEmpty else { return nil }
        return try QMIParser.data(fromHex: hex)
    }

    private static func optionalText(_ hex: String?) throws -> String? {
        guard let data = try optionalData(hex), let value = String(data: data, encoding: .utf8) else { return nil }
        return BandParser.clean(value)
    }
}

final class SystemSSHExecutor: @unchecked Sendable {
    private let sshPath: String
    private let askPassPath: String?

    init(
        sshPath: String = "/usr/bin/ssh",
        askPassPath: String? = ProcessInfo.processInfo.environment["MODEM_SIGNAL_ASKPASS_PATH"]
    ) {
        self.sshPath = sshPath
        self.askPassPath = askPassPath
    }

    func run(
        host: String,
        username: String,
        password: String,
        sourceAddress: String?,
        script: String,
        timeout: TimeInterval = 8
    ) async throws -> Data {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { [self] in
            try runBlocking(
                host: host,
                username: username,
                password: password,
                sourceAddress: sourceAddress,
                script: script,
                timeout: timeout
            )
        }
        do {
            let output = try await worker.value
            // The blocking Process remains isolated from Swift cooperative
            // cancellation. Re-check immediately after it returns so its
            // result cannot be mistaken for success by a retired task.
            try Task.checkCancellation()
            return output
        } catch {
            // A cancelled caller remains cancelled even if the detached SSH
            // process later exits with its own timeout/command error. Cleanup
            // tasks are newly created and therefore preserve their real error.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func runBlocking(
        host: String,
        username: String,
        password: String,
        sourceAddress: String?,
        script: String,
        timeout: TimeInterval
    ) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            throw VOSClientError.sshUnavailable
        }
        let helper = askPassPath
            ?? Bundle.main.path(forResource: "ModemSignalSSHAskPass", ofType: "sh")
        guard let helper, FileManager.default.isExecutableFile(atPath: helper) else {
            throw VOSClientError.askPassUnavailable
        }
        guard DeviceConfiguration.isLocalHost(host),
              !username.isEmpty,
              !username.contains(where: { $0.isWhitespace || $0 == "\0" })
        else { throw VOSClientError.invalidHost }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: sshPath)
        var arguments = [
            "-F", "/dev/null", "-4", "-T", "-x", "-a",
            "-o", "BatchMode=no",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "PubkeyAuthentication=no",
            "-o", "PasswordAuthentication=yes",
            "-o", "KbdInteractiveAuthentication=yes",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=3",
            "-o", "ConnectionAttempts=1",
            "-o", "ServerAliveInterval=2",
            "-o", "ServerAliveCountMax=1",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "CheckHostIP=no",
            "-o", "LogLevel=ERROR",
            "-o", "ControlMaster=no",
            "-o", "ClearAllForwardings=yes"
        ]
        if let sourceAddress { arguments += ["-b", sourceAddress] }
        arguments += ["-l", username, host, "/usr/bin/perl", "-"]
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = helper
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = "ModemSignalStatus:0"
        environment["MODEM_SIGNAL_SSH_PASSWORD"] = password
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw VOSClientError.sshUnavailable
        }
        input.fileHandleForWriting.write(Data(script.utf8))
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(max(1, timeout))
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning, Date() < grace { usleep(10_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw VOSClientError.timedOut
        }

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        guard stdout.count <= 131_072, stderr.count <= 131_072 else {
            throw VOSClientError.invalidResponse
        }
        guard process.terminationStatus == 0 else {
            throw classify(status: process.terminationStatus, stderr: stderr)
        }
        return stdout
    }

    private func classify(status: Int32, stderr: Data) -> VOSClientError {
        let raw = String(data: stderr, encoding: .utf8) ?? ""
        let lower = raw.lowercased()
        if lower.contains("permission denied") || lower.contains("authentication failed") {
            return .authenticationFailed
        }
        if lower.contains("no route") || lower.contains("connection refused") ||
            lower.contains("operation timed out") || lower.contains("network is unreachable") ||
            lower.contains("could not resolve") {
            return .unreachable
        }
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)
        if lower.contains("at command") || lower.contains("atcli") ||
            lower.contains("device identity") {
            return .commandFailed(
                message.isEmpty ? "The modem AT command failed (\(status))." : String(message)
            )
        }
        return .qmiUnavailable(message.isEmpty ? "remote probe failed (\(status))" : String(message))
    }
}

struct LocalInterfaceCandidate: Equatable, Sendable {
    let name: String
    let address: String
    let isActive: Bool
}

enum LocalInterface {
    static func vosInterfaceName() -> String? { vosInterface()?.name }
    static func vosSourceAddress() -> String? { vosInterface()?.address }

    static func selectVOSInterface(
        candidates: [LocalInterfaceCandidate],
        routedSourceAddress: String?
    ) -> LocalInterfaceCandidate? {
        let active = candidates.filter {
            $0.isActive && $0.address.hasPrefix("192.168.225.") && $0.address != "192.168.225.1"
        }
        if let routedSourceAddress,
           let routed = active.first(where: { $0.address == routedSourceAddress }) {
            return routed
        }
        return active.max { lhs, rhs in
            let lhsIndex = interfaceIndex(lhs.name)
            let rhsIndex = interfaceIndex(rhs.name)
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.address < rhs.address
        }
    }

    private static func interfaceIndex(_ name: String) -> Int {
        let suffix = name.reversed().prefix(while: { $0.isNumber }).reversed()
        return Int(String(suffix)) ?? -1
    }

    private static func vosInterface() -> LocalInterfaceCandidate? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var candidates: [LocalInterfaceCandidate] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var socketAddress = address.pointee
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                &socketAddress,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = decodeCString(host)
            guard ip.hasPrefix("192.168.225."), ip != "192.168.225.1" else { continue }
            let flags = interface.pointee.ifa_flags
            let isActive = flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0
            candidates.append(LocalInterfaceCandidate(
                name: String(cString: interface.pointee.ifa_name),
                address: ip,
                isActive: isActive
            ))
        }
        return selectVOSInterface(
            candidates: candidates,
            routedSourceAddress: routedSourceAddress(to: "192.168.225.1")
        )
    }

    private static func routedSourceAddress(to destination: String) -> String? {
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(22).bigEndian
        guard destination.withCString({ inet_pton(AF_INET, $0, &remote.sin_addr) }) == 1 else {
            return nil
        }
        let connected = withUnsafePointer(to: &remote) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard resolved == 0 else { return nil }

        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var address = local.sin_addr
        guard inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil else { return nil }
        return decodeCString(text)
    }

    private static func decodeCString(_ value: [CChar]) -> String {
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
