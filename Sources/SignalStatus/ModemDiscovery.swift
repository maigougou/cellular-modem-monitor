import Foundation

/// The stable part of a discovery candidate's identity. Private management
/// addresses commonly repeat on different links, so the interface index must
/// never be dropped when candidates are cached or de-duplicated.
struct ModemDiscoveryCandidateKey: Hashable, Sendable, CustomStringConvertible {
    let scheme: String
    let host: String
    let effectivePort: Int
    let interfaceIndex: UInt32

    init(scheme: String, host: String, port: Int?, interfaceIndex: UInt32) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        effectivePort = port ?? (scheme.lowercased() == "https" ? 443 : 80)
        self.interfaceIndex = interfaceIndex
    }

    var description: String {
        "\(scheme)://\(host):\(effectivePort)%\(interfaceIndex)"
    }
}

enum ModemDiscoveryCandidateSource: Int, CaseIterable, Hashable, Sendable {
    case knownDefault = 100
    case primaryInterface = 200
    case matchingGateway = 600
    case matchingSubnet = 700
    // An address the user entered now must outrank the cached endpoint from a
    // previous run. Otherwise a still-reachable old modem can make a Settings
    // change appear to have no effect.
    case lastSuccessful = 900
    case manual = 1_000
}

/// A caller-provided endpoint can optionally be pinned to an interface. An
/// unpinned hint is expanded once per eligible interface rather than being
/// handed to the system's default route as an ambiguous URL.
struct ModemEndpointHint: Hashable, Sendable {
    let kind: ModemKind
    let baseURL: URL
    let interfaceName: String?
    let interfaceIndex: UInt32?

    init(
        kind: ModemKind,
        baseURL: URL,
        interfaceName: String? = nil,
        interfaceIndex: UInt32? = nil
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
    }
}

struct ModemDiscoveryHints: Equatable, Sendable {
    var lastSuccessful: [ModemEndpointHint]
    var manual: [ModemEndpointHint]

    init(
        lastSuccessful: [ModemEndpointHint] = [],
        manual: [ModemEndpointHint] = []
    ) {
        self.lastSuccessful = lastSuccessful
        self.manual = manual
    }

    static let empty = ModemDiscoveryHints()
}

/// Discovery metadata supplied independently of a backend implementation.
/// Adding another modem only requires registering another profile; the
/// topology and probing algorithms remain unchanged.
struct ModemDiscoveryProfile: Hashable, Sendable {
    let kind: ModemKind
    let defaultBaseURLs: [URL]
    let probeTimeoutNanoseconds: UInt64

    init(
        kind: ModemKind,
        defaultBaseURLs: [URL],
        probeTimeoutNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.kind = kind
        self.defaultBaseURLs = defaultBaseURLs
        self.probeTimeoutNanoseconds = probeTimeoutNanoseconds
    }

    static let builtIn: [ModemDiscoveryProfile] = [
        ModemDiscoveryProfile(
            kind: .zteMC7530CA,
            defaultBaseURLs: [URL(string: "http://192.168.254.1")!],
            // Identification now performs anonymous schema/model checks,
            // login, and authenticated model/MSN verification. Allow the
            // complete local RPC chain to finish on a busy Wi-Fi interface.
            probeTimeoutNanoseconds: 5_000_000_000
        ),
        ModemDiscoveryProfile(
            kind: .vos5G,
            defaultBaseURLs: [URL(string: "http://192.168.225.1")!],
            // VOS identification starts an SSH probe whose own finite budget
            // is eight seconds. Discovery must not declare it absent first.
            probeTimeoutNanoseconds: 9_000_000_000
        )
    ]
}

struct ModemDiscoveryCandidate: Hashable, Sendable, Identifiable {
    let kind: ModemKind
    let endpoint: ScopedEndpoint
    let sources: Set<ModemDiscoveryCandidateSource>
    let priority: Int

    var key: ModemDiscoveryCandidateKey {
        ModemDiscoveryCandidateKey(
            scheme: endpoint.baseURL.scheme ?? "http",
            host: endpoint.host ?? endpoint.baseURL.absoluteString,
            port: endpoint.baseURL.port,
            interfaceIndex: endpoint.interfaceIndex ?? 0
        )
    }

    /// The kind is included because a manually supplied URL may intentionally
    /// be tried with more than one backend. The network key itself remains the
    /// required host + interface-index pair.
    var id: String { "\(kind.rawValue)|\(key.description)" }

    var orderedSources: [ModemDiscoveryCandidateSource] {
        sources.sorted { $0.rawValue > $1.rawValue }
    }
}

/// Pure candidate generation, separated from live topology collection and
/// network I/O so fixtures can exercise every route layout deterministically.
struct ModemCandidateGenerator: Sendable {
    private struct AggregateKey: Hashable {
        let candidateKey: ModemDiscoveryCandidateKey
        let kind: ModemKind
    }

    private struct Aggregate {
        var endpoint: ScopedEndpoint
        var sources: Set<ModemDiscoveryCandidateSource>
        var priority: Int
    }

    let profiles: [ModemDiscoveryProfile]

    init(profiles: [ModemDiscoveryProfile] = ModemDiscoveryProfile.builtIn) {
        self.profiles = profiles
    }

    func candidates(
        topology: NetworkTopologySnapshot,
        hints: ModemDiscoveryHints = .empty,
        allowedKinds: Set<ModemKind> = Set(ModemKind.allCases)
    ) -> [ModemDiscoveryCandidate] {
        let interfaces = topology.discoveryInterfaces.sorted(by: Self.interfaceOrder)
        guard !interfaces.isEmpty else { return [] }

        var aggregates: [AggregateKey: Aggregate] = [:]

        for interface in interfaces {
            for profile in profiles where allowedKinds.contains(profile.kind) {
                for baseURL in profile.defaultBaseURLs {
                    add(
                        kind: profile.kind,
                        baseURL: baseURL,
                        interface: interface,
                        source: .knownDefault,
                        to: &aggregates
                    )
                }
            }
        }

        add(
            hints: hints.manual.filter { allowedKinds.contains($0.kind) },
            source: .manual,
            interfaces: interfaces,
            to: &aggregates
        )
        add(
            hints: hints.lastSuccessful.filter { allowedKinds.contains($0.kind) },
            source: .lastSuccessful,
            interfaces: interfaces,
            to: &aggregates
        )

        return aggregates.map { aggregateKey, aggregate in
            ModemDiscoveryCandidate(
                kind: aggregateKey.kind,
                endpoint: aggregate.endpoint,
                sources: aggregate.sources,
                priority: aggregate.priority
            )
        }.sorted(by: Self.candidateOrder)
    }

    private func add(
        hints: [ModemEndpointHint],
        source: ModemDiscoveryCandidateSource,
        interfaces: [NetworkInterfaceSnapshot],
        to aggregates: inout [AggregateKey: Aggregate]
    ) {
        for hint in hints {
            guard Self.canonicalHTTPBaseURL(hint.baseURL) != nil else { continue }
            let explicitlyMatched = interfaces.filter { interface in
                if let index = hint.interfaceIndex, interface.index != index { return false }
                if let name = hint.interfaceName, interface.name != name { return false }
                return hint.interfaceIndex != nil || hint.interfaceName != nil
            }

            // A stale interface hint should not make a persisted/manual modem
            // disappear forever after macOS renumbers an enX interface.
            let targetInterfaces = explicitlyMatched.isEmpty ? interfaces : explicitlyMatched
            for interface in targetInterfaces {
                add(
                    kind: hint.kind,
                    baseURL: hint.baseURL,
                    interface: interface,
                    source: source,
                    to: &aggregates
                )
            }
        }
    }

    private func add(
        kind: ModemKind,
        baseURL: URL,
        interface: NetworkInterfaceSnapshot,
        source: ModemDiscoveryCandidateSource,
        to aggregates: inout [AggregateKey: Aggregate]
    ) {
        guard let canonicalURL = Self.canonicalHTTPBaseURL(baseURL),
              let host = canonicalURL.host?.lowercased()
        else { return }

        let address = IPv4HostAddress(string: host)
        let matchingAddress = address.flatMap { target in
            interface.addresses.first { $0.contains(target) }
        }
        let fallbackAddress = interface.addresses.first(where: {
            !$0.address.isLinkLocal
        }) ?? interface.addresses.first
        let sourceAddress = (matchingAddress ?? fallbackAddress)?.address.description
        let matchesGateway = address != nil && interface.router == address
        // Both USB ECM and RJ45 adapters appear as enX to these APIs. Mark a
        // same-link endpoint as unknown until an IOKit/device fingerprint can
        // safely distinguish directUSB from directEthernet.
        let connectionPath: ConnectionPath = (matchingAddress != nil || matchesGateway)
            ? .unknown
            : .routed
        let endpoint = ScopedEndpoint(
            baseURL: canonicalURL,
            interfaceName: interface.name,
            interfaceIndex: interface.index,
            sourceAddress: sourceAddress,
            connectionPath: connectionPath,
            gateway: interface.router?.description
        )
        let candidateKey = ModemDiscoveryCandidateKey(
            scheme: canonicalURL.scheme ?? "http",
            host: host,
            port: canonicalURL.port,
            interfaceIndex: interface.index
        )
        let aggregateKey = AggregateKey(
            candidateKey: candidateKey,
            kind: kind
        )

        var evidence: Set<ModemDiscoveryCandidateSource> = [source]
        if matchingAddress != nil { evidence.insert(.matchingSubnet) }
        if matchesGateway { evidence.insert(.matchingGateway) }
        if interface.isPrimary { evidence.insert(.primaryInterface) }
        let priority = evidence.map(\.rawValue).max() ?? source.rawValue

        if var existing = aggregates[aggregateKey] {
            existing.sources.formUnion(evidence)
            if priority > existing.priority {
                existing.endpoint = endpoint
                existing.priority = priority
            }
            aggregates[aggregateKey] = existing
        } else {
            aggregates[aggregateKey] = Aggregate(
                endpoint: endpoint,
                sources: evidence,
                priority: priority
            )
        }
    }

    private static func canonicalHTTPBaseURL(_ input: URL) -> URL? {
        guard let scheme = input.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              input.host != nil,
              input.user == nil,
              input.password == nil
        else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = input.host?.lowercased()
        components.port = input.port
        components.path = ""
        return components.url
    }

    private static func interfaceOrder(
        _ lhs: NetworkInterfaceSnapshot,
        _ rhs: NetworkInterfaceSnapshot
    ) -> Bool {
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.name < rhs.name
    }

    private static func candidateOrder(
        _ lhs: ModemDiscoveryCandidate,
        _ rhs: ModemDiscoveryCandidate
    ) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }

        let lhsDirect = lhs.endpoint.connectionPath != .routed
        let rhsDirect = rhs.endpoint.connectionPath != .routed
        if lhsDirect != rhsDirect { return lhsDirect }

        if lhs.key.host != rhs.key.host { return lhs.key.host < rhs.key.host }
        if lhs.key.interfaceIndex != rhs.key.interfaceIndex {
            return lhs.key.interfaceIndex < rhs.key.interfaceIndex
        }
        if lhs.key.scheme != rhs.key.scheme { return lhs.key.scheme < rhs.key.scheme }
        if lhs.key.effectivePort != rhs.key.effectivePort {
            return lhs.key.effectivePort < rhs.key.effectivePort
        }
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let lhsScheme = lhs.endpoint.baseURL.scheme ?? ""
        let rhsScheme = rhs.endpoint.baseURL.scheme ?? ""
        if lhsScheme != rhsScheme { return lhsScheme < rhsScheme }
        return (lhs.endpoint.baseURL.port ?? 0) < (rhs.endpoint.baseURL.port ?? 0)
    }
}

/// Discovery probes are intentionally transport-agnostic. A production probe
/// can call a backend's anonymous or two-stage `identify`, while tests inject
/// a closure and never touch the network.
protocol ModemDiscoveryProbing: Sendable {
    func identify(candidate: ModemDiscoveryCandidate) async throws -> ModemIdentity?
}

/// Carries structured evidence that a backend completed its anonymous product
/// preflight before authentication became necessary. This lets routed
/// known-default candidates surface the real credential prompt without making
/// every weak-topology authentication error look like a modem match.
struct ModemDiscoveryConfirmedProductFailure: Error, CustomStringConvertible,
    ModemFailureCategorizing, Sendable {
    let description: String
    let modemFailureCategory: ModemFailureCategory
}

struct ClosureModemDiscoveryProbe: ModemDiscoveryProbing {
    typealias Operation = @Sendable (ModemDiscoveryCandidate) async throws -> ModemIdentity?

    private let operation: Operation

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    func identify(candidate: ModemDiscoveryCandidate) async throws -> ModemIdentity? {
        try await operation(candidate)
    }
}

enum ModemDiscoveryProbeResult: Equatable, Sendable {
    case matched(ModemIdentity)
    case notMatched
    case timedOut
    case failed(
        String,
        category: ModemFailureCategory,
        confirmedProduct: Bool
    )
}

struct ModemDiscoveryAttempt: Equatable, Sendable {
    let candidate: ModemDiscoveryCandidate
    let result: ModemDiscoveryProbeResult
}

struct ModemDiscoveryReport: Equatable, Sendable {
    let topology: NetworkTopologySnapshot
    let attempts: [ModemDiscoveryAttempt]

    var matches: [ModemDiscoveryAttempt] {
        attempts.filter {
            if case .matched = $0.result { return true }
            return false
        }
    }
}

/// A single-resume race used to enforce the discovery deadline even when a
/// transport is slow to observe cooperative task cancellation. The losing
/// task is cancelled and may finish later; transports must still configure
/// their own finite resource/request timeout for eventual cleanup.
private final class ModemProbeRaceState: @unchecked Sendable {
    private let lock = NSLock()
    private var isResolved = false
    private var resolvedValue: ModemDiscoveryProbeResult?
    private var continuation: CheckedContinuation<ModemDiscoveryProbeResult, Never>?
    private var tasks: [Task<Void, Never>] = []

    /// Returns false when cancellation/deadline won before the continuation
    /// was installed; in that case the continuation is resumed immediately.
    func install(
        continuation newContinuation: CheckedContinuation<ModemDiscoveryProbeResult, Never>
    ) -> Bool {
        lock.lock()
        if isResolved {
            let value = resolvedValue ?? .timedOut
            lock.unlock()
            newContinuation.resume(returning: value)
            return false
        }
        continuation = newContinuation
        lock.unlock()
        return true
    }

    func install(tasks newTasks: [Task<Void, Never>]) {
        lock.lock()
        if isResolved {
            lock.unlock()
            newTasks.forEach { $0.cancel() }
            return
        }
        tasks = newTasks
        lock.unlock()
    }

    func resolve(_ value: ModemDiscoveryProbeResult) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        resolvedValue = value
        let continuationToResume = continuation
        continuation = nil
        let tasksToCancel = tasks
        tasks.removeAll(keepingCapacity: false)
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
        continuationToResume?.resume(returning: value)
    }
}

/// Re-snapshots the topology for every run. Probes execute in deterministic
/// priority batches, limiting traffic to private management endpoints while
/// preserving stable result order regardless of response timing.
struct ModemDiscoveryEngine: Sendable {
    let topologyProvider: any NetworkTopologyProviding
    let probe: any ModemDiscoveryProbing
    let profiles: [ModemDiscoveryProfile]
    let maximumConcurrentProbes: Int
    /// A test/diagnostic override. Production uses each backend profile's
    /// timeout so a fast HTTP modem is not forced to share SSH's larger budget.
    let probeTimeoutNanosecondsOverride: UInt64?

    init(
        topologyProvider: any NetworkTopologyProviding = SystemNetworkTopologyProvider(),
        probe: any ModemDiscoveryProbing,
        profiles: [ModemDiscoveryProfile] = ModemDiscoveryProfile.builtIn,
        maximumConcurrentProbes: Int = 4,
        probeTimeoutNanoseconds: UInt64? = nil
    ) {
        self.topologyProvider = topologyProvider
        self.probe = probe
        self.profiles = profiles
        self.maximumConcurrentProbes = max(1, maximumConcurrentProbes)
        self.probeTimeoutNanosecondsOverride = probeTimeoutNanoseconds
    }

    func candidates(
        hints: ModemDiscoveryHints = .empty,
        allowedKinds: Set<ModemKind> = Set(ModemKind.allCases)
    ) -> [ModemDiscoveryCandidate] {
        ModemCandidateGenerator(profiles: profiles).candidates(
            topology: topologyProvider.snapshot(),
            hints: hints,
            allowedKinds: allowedKinds
        )
    }

    func discover(
        hints: ModemDiscoveryHints = .empty,
        allowedKinds: Set<ModemKind> = Set(ModemKind.allCases)
    ) async -> ModemDiscoveryReport {
        let topology = topologyProvider.snapshot()
        let candidates = ModemCandidateGenerator(profiles: profiles).candidates(
            topology: topology,
            hints: hints,
            allowedKinds: allowedKinds
        )
        var attempts: [ModemDiscoveryAttempt] = []

        var batchStart = 0
        while batchStart < candidates.count, !Task.isCancelled {
            let batchEnd = min(batchStart + maximumConcurrentProbes, candidates.count)
            let batch = Array(candidates[batchStart..<batchEnd])
            let results = await withTaskGroup(
                of: (Int, ModemDiscoveryProbeResult).self,
                returning: [(Int, ModemDiscoveryProbeResult)].self
            ) { group in
                for (offset, candidate) in batch.enumerated() {
                    group.addTask {
                        let result = await probeOne(candidate)
                        return (offset, result)
                    }
                }

                var values: [(Int, ModemDiscoveryProbeResult)] = []
                for await value in group { values.append(value) }
                return values.sorted { $0.0 < $1.0 }
            }

            for (offset, result) in results {
                attempts.append(ModemDiscoveryAttempt(
                    candidate: batch[offset],
                    result: result
                ))
            }
            batchStart = batchEnd
        }

        return ModemDiscoveryReport(topology: topology, attempts: attempts)
    }

    private func probeOne(
        _ candidate: ModemDiscoveryCandidate
    ) async -> ModemDiscoveryProbeResult {
        let profileTimeout = profiles.first(where: { $0.kind == candidate.kind })?
            .probeTimeoutNanoseconds ?? 2_000_000_000
        let timeoutNanoseconds = probeTimeoutNanosecondsOverride ?? profileTimeout
        let race = ModemProbeRaceState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard race.install(continuation: continuation) else { return }

                let probeTask = Task {
                    let result: ModemDiscoveryProbeResult
                    do {
                        if let identity = try await probe.identify(candidate: candidate) {
                            result = .matched(identity)
                        } else {
                            result = .notMatched
                        }
                    } catch is CancellationError {
                        result = .timedOut
                    } catch {
                        result = .failed(
                            String(describing: error),
                            category: ModemFailureClassifier.category(of: error),
                            confirmedProduct: error is ModemDiscoveryConfirmedProductFailure
                        )
                    }
                    race.resolve(result)
                }
                let timerTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        race.resolve(.timedOut)
                    } catch {
                        // The probe won and cancelled its deadline task.
                    }
                }
                race.install(tasks: [probeTask, timerTask])
            }
        } onCancel: {
            race.resolve(.timedOut)
        }
    }
}
