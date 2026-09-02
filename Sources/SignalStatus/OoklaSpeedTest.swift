import Darwin
import Foundation

enum OoklaSpeedTestExecutable {
    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates: [String] = []
        if let override = environment["OOKLA_SPEEDTEST_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/speedtest",
            "/usr/local/bin/speedtest",
            "/opt/local/bin/speedtest"
        ])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/speedtest"
            })
        }

        var visited = Set<String>()
        for candidate in candidates where visited.insert(candidate).inserted {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

enum OoklaSpeedTestCommand {
    static func arguments() -> [String] {
        [
            "--format=json",
            "--progress=no",
            "--accept-license",
            "--accept-gdpr"
        ]
    }
}

struct OoklaSpeedTestProcessOutput: Equatable, Sendable {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
}

protocol OoklaSpeedTestProcessExecuting: Sendable {
    var availabilityError: SpeedTestError? { get }

    func execute() async throws -> OoklaSpeedTestProcessOutput
}

private final class OoklaSpeedTestProcessBox: @unchecked Sendable {
    let process: Process
    let standardOutput: Pipe
    let standardError: Pipe

    init(process: Process, standardOutput: Pipe, standardError: Pipe) {
        self.process = process
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

actor SystemOoklaSpeedTestProcess: OoklaSpeedTestProcessExecuting {
    nonisolated let availabilityError: SpeedTestError?

    private let executableURL: URL?
    private var executableVerified = false
    private var running: OoklaSpeedTestProcessBox?

    init(executableURL: URL? = OoklaSpeedTestExecutable.locate()) {
        self.executableURL = executableURL
        availabilityError = executableURL == nil ? .ooklaCLIUnavailable : nil
    }

    func execute() async throws -> OoklaSpeedTestProcessOutput {
        guard let executableURL else { throw SpeedTestError.ooklaCLIUnavailable }
        try verifyOfficialExecutable(executableURL)

        while running != nil {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try Task.checkCancellation()

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = OoklaSpeedTestCommand.arguments()
        process.standardOutput = standardOutput
        process.standardError = standardError
        let box = OoklaSpeedTestProcessBox(
            process: process,
            standardOutput: standardOutput,
            standardError: standardError
        )

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            running = box
            do {
                try process.run()
            } catch {
                if running === box { running = nil }
                throw SpeedTestError.launchFailed(error.localizedDescription)
            }
            defer {
                if running === box { running = nil }
            }

            let outputTask = Task.detached(priority: .utility) {
                box.standardOutput.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .utility) {
                box.standardError.fileHandleForReading.readDataToEndOfFile()
            }
            let statusTask = Task.detached(priority: .utility) { () -> Int32 in
                box.process.waitUntilExit()
                return box.process.terminationStatus
            }

            let status = await statusTask.value
            let output = await outputTask.value
            let error = await errorTask.value
            try Task.checkCancellation()
            return OoklaSpeedTestProcessOutput(
                standardOutput: output,
                standardError: error,
                terminationStatus: status
            )
        } onCancel: {
            Task { await self.cancel(target: box) }
        }
    }

    private func verifyOfficialExecutable(_ executableURL: URL) throws {
        guard !executableVerified else { return }

        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            throw SpeedTestError.launchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        var versionData = output.fileHandleForReading.readDataToEndOfFile()
        versionData.append(error.fileHandleForReading.readDataToEndOfFile())
        let version = String(decoding: versionData, as: UTF8.self)
        guard process.terminationStatus == 0,
              version.localizedCaseInsensitiveContains("Speedtest by Ookla")
        else { throw SpeedTestError.ooklaCLIIncompatible }
        executableVerified = true
    }

    private func cancel(target: OoklaSpeedTestProcessBox) async {
        guard running === target else { return }
        if target.process.isRunning {
            target.process.terminate()
        }
        for _ in 0..<100 {
            if running !== target { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if running === target, target.process.isRunning {
            Darwin.kill(target.process.processIdentifier, SIGKILL)
        }
        for _ in 0..<100 {
            if running !== target { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

struct OoklaRouteProof: Equatable, Sendable {
    let interfaceName: String
    let interfaceIndex: UInt32
    let sourceAddresses: Set<String>
}

protocol OoklaRouteValidating: Sendable {
    func capture(binding: SpeedTestBinding) throws -> OoklaRouteProof
    func validate(proof: OoklaRouteProof) throws
}

struct SystemOoklaRouteValidator: OoklaRouteValidating {
    private let topologyProvider: any NetworkTopologyProviding

    init(
        topologyProvider: any NetworkTopologyProviding = SystemNetworkTopologyProvider()
    ) {
        self.topologyProvider = topologyProvider
    }

    func capture(binding: SpeedTestBinding) throws -> OoklaRouteProof {
        let topology = topologyProvider.snapshot()
        let interface = try validatedInterface(
            named: binding.interfaceName,
            index: binding.interfaceIndex,
            topology: topology
        )
        try validateDefaultRoutes(
            expectedInterface: binding.interfaceName,
            topology: topology
        )
        let addresses = Set(interface.allAddresses)
        guard !addresses.isEmpty else {
            throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
        }
        return OoklaRouteProof(
            interfaceName: binding.interfaceName,
            interfaceIndex: binding.interfaceIndex,
            sourceAddresses: addresses
        )
    }

    func validate(proof: OoklaRouteProof) throws {
        let topology = topologyProvider.snapshot()
        _ = try validatedInterface(
            named: proof.interfaceName,
            index: proof.interfaceIndex,
            topology: topology
        )
        try validateDefaultRoutes(
            expectedInterface: proof.interfaceName,
            topology: topology
        )
    }

    private func validatedInterface(
        named name: String,
        index: UInt32,
        topology: NetworkTopologySnapshot
    ) throws -> NetworkInterfaceSnapshot {
        guard let interface = topology.interfaces.first(where: { $0.name == name }) else {
            throw SpeedTestError.interfaceUnavailable(name)
        }
        guard interface.index == index else {
            throw SpeedTestError.interfaceIndexChanged(
                expected: index,
                actual: interface.index
            )
        }
        guard interface.kind == .physical, interface.isUp, interface.isRunning else {
            throw SpeedTestError.interfaceInactive(name)
        }
        return interface
    }

    private func validateDefaultRoutes(
        expectedInterface: String,
        topology: NetworkTopologySnapshot
    ) throws {
        let primaryInterfaces = Set([
            topology.primaryIPv4InterfaceName,
            topology.primaryIPv6InterfaceName
        ].compactMap { $0 })
        guard !primaryInterfaces.isEmpty else {
            throw SpeedTestError.defaultRouteUnavailable
        }
        guard primaryInterfaces == [expectedInterface] else {
            throw SpeedTestError.defaultRouteMismatch(
                expected: expectedInterface,
                actual: primaryInterfaces.sorted()
            )
        }
    }
}

enum OoklaSpeedTestResultParser {
    static func parse(
        _ data: Data,
        binding: SpeedTestBinding,
        routeProof: OoklaRouteProof,
        completedAt: Date = Date()
    ) throws -> SpeedTestResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              string(dictionary["type"]) == "result",
              let interface = dictionary["interface"] as? [String: Any]
        else { throw SpeedTestError.invalidResult }

        guard let reportedInterface = string(interface["name"]),
              !reportedInterface.isEmpty
        else { throw SpeedTestError.reportedInterfaceMissing }
        guard reportedInterface == binding.interfaceName else {
            throw SpeedTestError.reportedInterfaceMismatch(
                expected: binding.interfaceName,
                actual: reportedInterface
            )
        }
        let actualAddress = string(interface["internalIp"])
        guard let actualAddress,
              routeProof.sourceAddresses.contains(actualAddress)
        else {
            throw SpeedTestError.reportedSourceAddressMismatch(
                expected: routeProof.sourceAddresses.sorted().joined(separator: ", "),
                actual: actualAddress
            )
        }

        guard let download = dictionary["download"] as? [String: Any],
              let upload = dictionary["upload"] as? [String: Any],
              let downloadBytesPerSecond = number(download["bandwidth"]),
              let uploadBytesPerSecond = number(upload["bandwidth"]),
              downloadBytesPerSecond.isFinite,
              uploadBytesPerSecond.isFinite,
              downloadBytesPerSecond >= 0,
              uploadBytesPerSecond >= 0
        else { throw SpeedTestError.invalidResult }

        let ping = dictionary["ping"] as? [String: Any]
        let server = dictionary["server"] as? [String: Any]
        let result = dictionary["result"] as? [String: Any]
        let serverName = [string(server?["name"]), string(server?["location"])]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let resultURL = string(result?["url"]).flatMap(URL.init(string:))

        return SpeedTestResult(
            binding: binding,
            downloadBitsPerSecond: downloadBytesPerSecond * 8,
            uploadBitsPerSecond: uploadBytesPerSecond * 8,
            idleLatencyMilliseconds: number(ping?["latency"]),
            jitterMilliseconds: number(ping?["jitter"]),
            packetLossPercent: number(dictionary["packetLoss"]),
            serverName: serverName.isEmpty ? nil : serverName,
            resultURL: resultURL,
            completedAt: completedAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}

enum OoklaSpeedTestFailureSummary {
    static func summarize(standardOutput: Data, standardError: Data) -> String {
        var combined = standardOutput
        if !combined.isEmpty, !standardError.isEmpty { combined.append(0x0a) }
        combined.append(standardError)
        let text = String(decoding: combined, as: UTF8.self)
        var messages: [String] = []
        var seen = Set<String>()

        for line in text.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let message: String
            if let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any],
               let decoded = dictionary["message"] as? String {
                message = decoded
            } else {
                message = raw
            }
            guard !message.hasPrefix("bind("), seen.insert(message).inserted else {
                continue
            }
            messages.append(message)
        }

        return String(messages.suffix(3).joined(separator: " · ").prefix(300))
    }
}

actor OoklaSpeedTestRunner: SpeedTestRunning {
    private enum RunEvent: Sendable {
        case processFinished(OoklaSpeedTestProcessOutput)
        case monitorStopped
        case timedOut
    }

    nonisolated let availabilityError: SpeedTestError?

    private let process: any OoklaSpeedTestProcessExecuting
    private let trafficReader: any NetworkInterfaceTrafficReading
    private let routeValidator: any OoklaRouteValidating
    private let maximumRuntime: TimeInterval
    private let sampleIntervalNanoseconds: UInt64

    init(
        process: any OoklaSpeedTestProcessExecuting = SystemOoklaSpeedTestProcess(),
        trafficReader: any NetworkInterfaceTrafficReading = SystemNetworkInterfaceTrafficReader(),
        routeValidator: any OoklaRouteValidating = SystemOoklaRouteValidator(),
        maximumRuntime: TimeInterval = 90,
        sampleIntervalNanoseconds: UInt64 = 350_000_000
    ) {
        self.process = process
        self.trafficReader = trafficReader
        self.routeValidator = routeValidator
        self.maximumRuntime = maximumRuntime
        self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
        availabilityError = process.availabilityError
    }

    func run(
        binding: SpeedTestBinding,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult {
        if let availabilityError { throw availabilityError }
        let routeProof = try routeValidator.capture(binding: binding)
        let initial = try trafficReader.read(binding: binding)
        let process = self.process
        let trafficReader = self.trafficReader
        let routeValidator = self.routeValidator
        let maximumRuntime = self.maximumRuntime
        let sampleIntervalNanoseconds = self.sampleIntervalNanoseconds

        let output = try await withThrowingTaskGroup(of: RunEvent.self) { group in
            group.addTask {
                .processFinished(try await process.execute())
            }
            group.addTask {
                var prior = initial
                var smoothedDownload = 0.0
                var smoothedUpload = 0.0
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: sampleIntervalNanoseconds)
                    try routeValidator.validate(proof: routeProof)
                    let next = try trafficReader.read(binding: binding)
                    let interval = Self.seconds(prior.sampledAt.duration(to: next.sampledAt))
                    let received = next.receivedBytes >= prior.receivedBytes
                        ? next.receivedBytes - prior.receivedBytes
                        : 0
                    let sent = next.sentBytes >= prior.sentBytes
                        ? next.sentBytes - prior.sentBytes
                        : 0
                    let currentDownload = Double(received) * 8 / max(0.001, interval)
                    let currentUpload = Double(sent) * 8 / max(0.001, interval)
                    smoothedDownload = smoothedDownload == 0
                        ? currentDownload
                        : smoothedDownload * 0.62 + currentDownload * 0.38
                    smoothedUpload = smoothedUpload == 0
                        ? currentUpload
                        : smoothedUpload * 0.62 + currentUpload * 0.38
                    await progress(SpeedTestProgress(
                        downloadBitsPerSecond: smoothedDownload,
                        uploadBitsPerSecond: smoothedUpload,
                        elapsed: Self.seconds(initial.sampledAt.duration(to: next.sampledAt))
                    ))
                    prior = next
                }
                return .monitorStopped
            }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(max(1, maximumRuntime) * 1_000_000_000)
                )
                return .timedOut
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw SpeedTestError.invalidResult
            }
            switch first {
            case let .processFinished(output): return output
            case .monitorStopped: throw CancellationError()
            case .timedOut: throw SpeedTestError.commandTimedOut
            }
        }

        try routeValidator.validate(proof: routeProof)
        _ = try trafficReader.read(binding: binding)
        try Task.checkCancellation()
        guard output.terminationStatus == 0 else {
            let detail = OoklaSpeedTestFailureSummary.summarize(
                standardOutput: output.standardOutput,
                standardError: output.standardError
            )
            throw SpeedTestError.commandFailed(
                status: output.terminationStatus,
                detail: detail
            )
        }
        return try OoklaSpeedTestResultParser.parse(
            output.standardOutput,
            binding: binding,
            routeProof: routeProof
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
