import Darwin
import Foundation

enum VOSClientError: LocalizedError, Equatable {
    case invalidHost
    case unreachable
    case authenticationFailed
    case sshUnavailable
    case askPassUnavailable
    case timedOut
    case qmiUnavailable(String?)
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
            return "The read-only modem status query timed out."
        case let .qmiUnavailable(message):
            return message.map { "Modem QMI is unavailable: \($0)" } ?? "Modem QMI is unavailable."
        case .invalidResponse:
            return "The modem SSH/QMI probe returned an unreadable response."
        }
    }
}

actor VOSClient {
    private let executor: SystemSSHExecutor

    init(executor: SystemSSHExecutor = SystemSSHExecutor()) {
        self.executor = executor
    }

    func fetchSnapshot(configuration: DeviceConfiguration) async throws -> DeviceSnapshot {
        guard let host = configuration.sshHost else { throw VOSClientError.invalidHost }
        let sourceAddress = host == "192.168.225.1" ? LocalInterface.vosSourceAddress() : nil
        let output = try await executor.run(
            host: host,
            username: configuration.username,
            password: configuration.password,
            sourceAddress: sourceAddress,
            script: Self.readOnlyProbe
        )
        let probe = try VOSProbeOutput.parse(output)
        return try Self.makeSnapshot(
            host: host,
            interfaceName: LocalInterface.vosInterfaceName(),
            probe: probe
        )
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
        } catch {
            throw VOSClientError.qmiUnavailable(error.localizedDescription)
        }

        let nrReadings = radios.filter { $0.kind == .nr }
        let lteReadings = radios.filter { $0.kind == .lte }
        let nr = nrReadings.first
        let lte = lteReadings.first
        let signal = probe.signal.flatMap { try? QMIParser.signalInfo(from: $0) }
        let serving = probe.serving.flatMap { try? QMIParser.servingInfo(from: $0) }
        let explicitMode: NRSystemMode? = {
            guard nr != nil, let dsd = probe.dsd else { return nil }
            return try? QMIParser.systemMode(from: dsd)
        }()

        let secondaryLTE = probe.ca.flatMap { try? QMIParser.lteSecondaryBands(from: $0) } ?? []

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
            nrSignalDBm: signal?.nrRSRP,
            lteBand: lte?.band,
            lteChannel: lte.map { String($0.channel) },
            lteBandwidthMHz: lte?.bandwidthMHz,
            lteRaw: lte?.rawDescription,
            lteSignalDBm: signal?.lteRSRP,
            lteSecondaryCells: secondaryLTE,
            moduleVersion: cleanModemVersion(probe.modemVersion),
            deviceFirmware: cleanVOSVersion(probe.deviceFirmware),
            updatedAt: now
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
emit_hex("DSD_HEX", $endpoint{42} ? optional_qmi($endpoint{42}, 1, 0x0024) : "");
emit_hex("MODEM_HEX", modem_version());
emit_hex("DEVICE_HEX", read_file("/oem/cei_module_ver_vos_id"));

alarm 0;
"""#
}

struct VOSProbeOutput: Equatable, Sendable {
    let band: Data
    let signal: Data?
    let serving: Data?
    let ca: Data?
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
        script: String
    ) async throws -> Data {
        try await Task.detached(priority: .utility) { [self] in
            try runBlocking(
                host: host,
                username: username,
                password: password,
                sourceAddress: sourceAddress,
                script: script
            )
        }.value
    }

    private func runBlocking(
        host: String,
        username: String,
        password: String,
        sourceAddress: String?,
        script: String
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

        let deadline = Date().addingTimeInterval(8)
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
        return .qmiUnavailable(message.isEmpty ? "remote probe failed (\(status))" : String(message))
    }
}

enum LocalInterface {
    static func vosInterfaceName() -> String? { vosInterface()?.name }
    static func vosSourceAddress() -> String? { vosInterface()?.address }

    private static func vosInterface() -> (name: String, address: String)? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

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
            let ip = String(cString: host)
            guard ip.hasPrefix("192.168.225."), ip != "192.168.225.1" else { continue }
            return (String(cString: interface.pointee.ifa_name), ip)
        }
        return nil
    }
}
