import Foundation

/// User-visible backend preference. Raw values are stable because this value is
/// stored in application preferences across releases.
enum ModemSelection: String, CaseIterable, Codable, Hashable, Sendable {
    case automatic
    case vos5G
    case zteMC7530CA

    var selectedKind: ModemKind? {
        switch self {
        case .automatic: return nil
        case .vos5G: return .vos5G
        case .zteMC7530CA: return .zteMC7530CA
        }
    }

    func allowedKinds(registeredKinds: Set<ModemKind>) -> Set<ModemKind> {
        guard let selectedKind else { return registeredKinds }
        return registeredKinds.contains(selectedKind) ? [selectedKind] : []
    }
}

/// Non-secret connection preferences suitable for UserDefaults or a property
/// list. Passwords are supplied separately through `ModemConnectionCredentials`
/// and should be backed by Keychain.
struct ModemConnectionPreferences: Codable, Equatable, Sendable {
    var selection: ModemSelection
    var manualEndpoints: [ModemEndpointPreference]
    var lastSuccessfulScopeKey: String?
    var lastSuccessfulEndpoint: ModemEndpointPreference?

    init(
        selection: ModemSelection = .automatic,
        manualEndpoints: [ModemEndpointPreference] = [],
        lastSuccessfulScopeKey: String? = nil,
        lastSuccessfulEndpoint: ModemEndpointPreference? = nil
    ) {
        self.selection = selection
        self.manualEndpoints = manualEndpoints
        self.lastSuccessfulScopeKey = lastSuccessfulScopeKey
        self.lastSuccessfulEndpoint = lastSuccessfulEndpoint
    }

    var discoveryHints: ModemDiscoveryHints {
        ModemDiscoveryHints(
            lastSuccessful: lastSuccessfulEndpoint.map { [$0.hint] } ?? [],
            manual: manualEndpoints.map(\.hint)
        )
    }
}

/// Codable representation of a discovery hint. Discovery's runtime value stays
/// focused on topology generation and does not itself need persistence logic.
struct ModemEndpointPreference: Codable, Equatable, Hashable, Sendable {
    var kind: ModemKind
    var baseURL: URL
    var interfaceName: String?
    var interfaceIndex: UInt32?

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

    init(_ hint: ModemEndpointHint) {
        self.init(
            kind: hint.kind,
            baseURL: hint.baseURL,
            interfaceName: hint.interfaceName,
            interfaceIndex: hint.interfaceIndex
        )
    }

    var hint: ModemEndpointHint {
        ModemEndpointHint(
            kind: kind,
            baseURL: baseURL,
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex
        )
    }
}

/// Secrets loaded for the current process. Keeping them out of
/// `ModemConnectionPreferences` prevents accidental serialization.
struct ModemConnectionCredentials: Equatable, Sendable {
    private var values: [ModemKind: ModemCredentials]

    init(_ values: [ModemKind: ModemCredentials] = [:]) {
        self.values = values
    }

    subscript(kind: ModemKind) -> ModemCredentials? {
        get { values[kind] }
        set { values[kind] = newValue }
    }
}

enum ModemCredentialPolicy: Equatable, Sendable {
    /// Identification or reads must not receive a configured password.
    case anonymous
    /// Use the configured credential only if it has the expected transport.
    case configured(ModemCredentialKind)

    fileprivate func resolve(
        kind: ModemKind,
        credentials: ModemConnectionCredentials
    ) throws -> ModemCredentials {
        switch self {
        case .anonymous:
            return .none
        case let .configured(expected):
            guard let configured = credentials[kind] else {
                throw ModemBackendError.credentialsRequired(expected)
            }
            guard configured.kind == expected else {
                throw ModemBackendError.incompatibleCredentials(
                    expected: expected,
                    actual: configured.kind
                )
            }
            return configured
        }
    }
}

/// One registry entry describes both the implementation and its discovery/
/// credential policy. Adding a modem does not require another coordinator
/// switch: register a backend and profile here instead.
struct ModemBackendRegistration: Sendable {
    let backend: any ModemStatusBackend
    let discoveryProfile: ModemDiscoveryProfile
    let identificationCredentials: ModemCredentialPolicy
    let statusCredentials: ModemCredentialPolicy

    init(
        backend: any ModemStatusBackend,
        discoveryProfile: ModemDiscoveryProfile,
        identificationCredentials: ModemCredentialPolicy,
        statusCredentials: ModemCredentialPolicy
    ) {
        self.backend = backend
        self.discoveryProfile = discoveryProfile
        self.identificationCredentials = identificationCredentials
        self.statusCredentials = statusCredentials
    }

    var kind: ModemKind { backend.kind }
}

enum ModemCoordinatorError: LocalizedError, Equatable, Sendable, ModemFailureCategorizing {
    case duplicateBackend(ModemKind)
    case mismatchedDiscoveryProfile(backend: ModemKind, profile: ModemKind)
    case missingDiscoveryProfile(ModemKind)
    case selectedBackendNotRegistered(ModemKind)
    case noMatchingModem
    case discoveredKindMismatch(expected: ModemKind, actual: ModemKind)
    case candidateIdentificationFailed([String])
    case allMatchedModemsFailed([String])
    case authenticationFailed(kind: ModemKind?, messages: [String])
    case qmiUnavailable(kind: ModemKind?, messages: [String])

    var errorDescription: String? {
        switch self {
        case let .duplicateBackend(kind):
            return "More than one backend was registered for \(kind.displayName)."
        case let .mismatchedDiscoveryProfile(backend, profile):
            return "The \(backend.displayName) backend was paired with the \(profile.displayName) discovery profile."
        case let .missingDiscoveryProfile(kind):
            return "No discovery profile is configured for \(kind.displayName)."
        case let .selectedBackendNotRegistered(kind):
            return "The selected \(kind.displayName) backend is not installed."
        case .noMatchingModem:
            return "No supported cellular modem was found on an active network interface."
        case let .discoveredKindMismatch(expected, actual):
            return "A \(expected.displayName) probe returned a \(actual.displayName) identity."
        case let .candidateIdentificationFailed(messages):
            let detail = messages.filter { !$0.isEmpty }.joined(separator: "; ")
            return detail.isEmpty
                ? "A likely modem endpoint was found, but its identity could not be verified."
                : "A likely modem endpoint was found, but identification failed: \(detail)"
        case let .allMatchedModemsFailed(messages):
            let detail = messages.filter { !$0.isEmpty }.joined(separator: "; ")
            return detail.isEmpty
                ? "Supported modems were found, but none returned a status snapshot."
                : "Supported modems were found, but status collection failed: \(detail)"
        case let .authenticationFailed(kind, messages):
            let subject = kind?.displayName ?? "The modem"
            let detail = messages.filter { !$0.isEmpty }.joined(separator: "; ")
            return detail.isEmpty
                ? "\(subject) authentication failed."
                : "\(subject) authentication failed: \(detail)"
        case let .qmiUnavailable(kind, messages):
            let subject = kind?.displayName ?? "The modem"
            let detail = messages.filter { !$0.isEmpty }.joined(separator: "; ")
            return detail.isEmpty
                ? "\(subject) QMI is unavailable."
                : "\(subject) QMI is unavailable: \(detail)"
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

private struct CoordinatedModemFailure: Equatable, Hashable, Sendable {
    let kind: ModemKind
    let category: ModemFailureCategory
    let message: String
}

struct ModemBackendRegistry: Sendable {
    private let registrations: [ModemKind: ModemBackendRegistration]

    init(registrations: [ModemBackendRegistration]) throws {
        var values: [ModemKind: ModemBackendRegistration] = [:]
        for registration in registrations {
            guard registration.discoveryProfile.kind == registration.kind else {
                throw ModemCoordinatorError.mismatchedDiscoveryProfile(
                    backend: registration.kind,
                    profile: registration.discoveryProfile.kind
                )
            }
            guard values[registration.kind] == nil else {
                throw ModemCoordinatorError.duplicateBackend(registration.kind)
            }
            values[registration.kind] = registration
        }
        self.registrations = values
    }

    var registeredKinds: Set<ModemKind> { Set(registrations.keys) }

    var discoveryProfiles: [ModemDiscoveryProfile] {
        registrations.values
            .map(\.discoveryProfile)
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    func registration(for kind: ModemKind) -> ModemBackendRegistration? {
        registrations[kind]
    }

    /// The production registry and credential policy live in one place so UI
    /// and status-model code do not need to know how either modem authenticates.
    static func standard(
        vosClient: VOSClient = VOSClient(),
        zteHTTPTransport: any ZTEHTTPTransport = NetworkBoundZTEHTTPTransport()
    ) throws -> ModemBackendRegistry {
        let profiles = Dictionary(
            uniqueKeysWithValues: ModemDiscoveryProfile.builtIn.map { ($0.kind, $0) }
        )
        guard let vosProfile = profiles[.vos5G] else {
            throw ModemCoordinatorError.missingDiscoveryProfile(.vos5G)
        }
        guard let zteProfile = profiles[.zteMC7530CA] else {
            throw ModemCoordinatorError.missingDiscoveryProfile(.zteMC7530CA)
        }

        return try ModemBackendRegistry(registrations: [
            ModemBackendRegistration(
                backend: VOSBackend(client: vosClient),
                discoveryProfile: vosProfile,
                identificationCredentials: .configured(.ssh),
                statusCredentials: .configured(.ssh)
            ),
            ModemBackendRegistration(
                backend: MC7530Backend(httpTransport: zteHTTPTransport),
                discoveryProfile: zteProfile,
                identificationCredentials: .anonymous,
                statusCredentials: .configured(.web)
            )
        ])
    }
}

struct ActiveModem: Equatable, Sendable, Identifiable {
    let identity: ModemIdentity
    let endpoint: ScopedEndpoint
    let capabilities: ModemCapability

    var id: String {
        identity.stableIdentifier ?? "\(identity.kind.rawValue)|\(endpoint.scopeKey)"
    }

    var endpointPreference: ModemEndpointPreference {
        ModemEndpointPreference(
            kind: identity.kind,
            baseURL: endpoint.baseURL,
            interfaceName: endpoint.interfaceName,
            interfaceIndex: endpoint.interfaceIndex
        )
    }
}

struct ModemReadResult: Equatable, Sendable {
    let activeModem: ActiveModem
    let snapshot: DeviceSnapshot
    let reusedActiveEndpoint: Bool
    let discoveryReport: ModemDiscoveryReport?

    var lastSuccessfulScopeKey: String { activeModem.endpoint.scopeKey }
    var lastSuccessfulEndpoint: ModemEndpointPreference { activeModem.endpointPreference }
}

/// Registry-backed probe used by the production discovery engine. Credential
/// policy is evaluated before the backend call, guaranteeing that the ZTE
/// identity probe remains anonymous while VOS identification uses SSH.
private struct RegistryModemDiscoveryProbe: ModemDiscoveryProbing {
    let registry: ModemBackendRegistry
    let credentials: ModemConnectionCredentials

    func identify(candidate: ModemDiscoveryCandidate) async throws -> ModemIdentity? {
        guard let registration = registry.registration(for: candidate.kind) else { return nil }
        let identityCredentials = try registration.identificationCredentials.resolve(
            kind: candidate.kind,
            credentials: credentials
        )
        guard let identity = try await registration.backend.identify(
            endpoint: candidate.endpoint,
            credentials: identityCredentials
        ) else { return nil }
        guard identity.kind == candidate.kind else {
            throw ModemCoordinatorError.discoveredKindMismatch(
                expected: candidate.kind,
                actual: identity.kind
            )
        }
        return identity
    }
}

actor ModemCoordinator {
    typealias DiscoveryOperation = @Sendable (
        _ hints: ModemDiscoveryHints,
        _ allowedKinds: Set<ModemKind>,
        _ credentials: ModemConnectionCredentials
    ) async -> ModemDiscoveryReport

    private let registry: ModemBackendRegistry
    private let discoverOperation: DiscoveryOperation
    private var activeModem: ActiveModem?
    private(set) var lastDiscoveryReport: ModemDiscoveryReport?

    /// Production initializer. The topology provider and backend registry are
    /// still injectable, and every discovery run receives the latest credentials.
    init(
        registry: ModemBackendRegistry,
        topologyProvider: any NetworkTopologyProviding = SystemNetworkTopologyProvider(),
        maximumConcurrentProbes: Int = 4,
        probeTimeoutNanoseconds: UInt64? = nil
    ) {
        self.registry = registry
        self.discoverOperation = { hints, allowedKinds, credentials in
            let probe = RegistryModemDiscoveryProbe(
                registry: registry,
                credentials: credentials
            )
            let engine = ModemDiscoveryEngine(
                topologyProvider: topologyProvider,
                probe: probe,
                profiles: registry.discoveryProfiles,
                maximumConcurrentProbes: maximumConcurrentProbes,
                probeTimeoutNanoseconds: probeTimeoutNanoseconds
            )
            return await engine.discover(hints: hints, allowedKinds: allowedKinds)
        }
    }

    /// Test initializer. A mock operation can return fixture reports without
    /// collecting the host topology or opening a network connection.
    init(
        registry: ModemBackendRegistry,
        discover: @escaping DiscoveryOperation
    ) {
        self.registry = registry
        self.discoverOperation = discover
    }

    func currentActiveModem() -> ActiveModem? { activeModem }

    func invalidateActiveModem() {
        activeModem = nil
    }

    func read(
        preferences: ModemConnectionPreferences,
        credentials: ModemConnectionCredentials
    ) async throws -> ModemReadResult {
        var priorStructuredFailure: CoordinatedModemFailure?
        let allowedKinds = preferences.selection.allowedKinds(
            registeredKinds: registry.registeredKinds
        )
        if let selectedKind = preferences.selection.selectedKind,
           !registry.registeredKinds.contains(selectedKind) {
            throw ModemCoordinatorError.selectedBackendNotRegistered(selectedKind)
        }

        // For an explicitly selected backend, reject a missing/wrong credential
        // transport before expanding one candidate per interface. This avoids
        // turning a Settings error into a burst of identical discovery probes.
        if let selectedKind = preferences.selection.selectedKind,
           let registration = registry.registration(for: selectedKind) {
            _ = try registration.identificationCredentials.resolve(
                kind: selectedKind,
                credentials: credentials
            )
            _ = try registration.statusCredentials.resolve(
                kind: selectedKind,
                credentials: credentials
            )
        }

        if let current = activeModem, allowedKinds.contains(current.identity.kind) {
            do {
                let snapshot = try await fetchSnapshot(
                    active: current,
                    credentials: credentials
                )
                return ModemReadResult(
                    activeModem: current,
                    snapshot: snapshot,
                    reusedActiveEndpoint: true,
                    discoveryReport: nil
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Re-snapshot topology and identify candidates after any failed
                // read. The old endpoint is not trusted again unless discovery
                // positively identifies it in the new topology.
                let category = ModemFailureClassifier.category(of: error)
                if category != .other {
                    priorStructuredFailure = CoordinatedModemFailure(
                        kind: current.identity.kind,
                        category: category,
                        message: error.localizedDescription
                    )
                }
                activeModem = nil
            }
        } else if activeModem != nil {
            activeModem = nil
        }

        guard !allowedKinds.isEmpty else {
            throw ModemCoordinatorError.noMatchingModem
        }

        let report = await discoverOperation(
            preferences.discoveryHints,
            allowedKinds,
            credentials
        )
        lastDiscoveryReport = report
        let matches = rankedMatches(
            in: report,
            preferredScopeKey: preferences.lastSuccessfulScopeKey
        )
        guard !matches.isEmpty else {
            var failures = relevantIdentificationFailures(
                in: report,
                includeAll: preferences.selection.selectedKind != nil
            )
            if let priorStructuredFailure {
                failures.append(priorStructuredFailure)
            }
            if let structuredError = structuredCoordinatorError(for: failures) {
                throw structuredError
            }
            if !failures.isEmpty {
                throw ModemCoordinatorError.candidateIdentificationFailed(
                    deduplicatedMessages(from: failures)
                )
            }
            throw ModemCoordinatorError.noMatchingModem
        }

        var failures = priorStructuredFailure.map { [$0] } ?? []
        for match in matches {
            do {
                let active = try makeActiveModem(from: match)
                let snapshot = try await fetchSnapshot(
                    active: active,
                    credentials: credentials
                )
                activeModem = active
                return ModemReadResult(
                    activeModem: active,
                    snapshot: snapshot,
                    reusedActiveEndpoint: false,
                    discoveryReport: report
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(CoordinatedModemFailure(
                    kind: match.candidate.kind,
                    category: ModemFailureClassifier.category(of: error),
                    message: error.localizedDescription
                ))
            }
        }
        if let structuredError = structuredCoordinatorError(for: failures) {
            throw structuredError
        }
        throw ModemCoordinatorError.allMatchedModemsFailed(
            deduplicatedMessages(from: failures)
        )
    }

    private func fetchSnapshot(
        active: ActiveModem,
        credentials: ModemConnectionCredentials
    ) async throws -> DeviceSnapshot {
        guard let registration = registry.registration(for: active.identity.kind) else {
            throw ModemCoordinatorError.selectedBackendNotRegistered(active.identity.kind)
        }
        let statusCredentials = try registration.statusCredentials.resolve(
            kind: active.identity.kind,
            credentials: credentials
        )
        return try await registration.backend.fetchSnapshot(
            endpoint: active.endpoint,
            credentials: statusCredentials
        )
    }

    private func makeActiveModem(
        from attempt: ModemDiscoveryAttempt
    ) throws -> ActiveModem {
        guard case let .matched(identity) = attempt.result else {
            throw ModemCoordinatorError.noMatchingModem
        }
        guard identity.kind == attempt.candidate.kind else {
            throw ModemCoordinatorError.discoveredKindMismatch(
                expected: attempt.candidate.kind,
                actual: identity.kind
            )
        }
        guard let registration = registry.registration(for: identity.kind) else {
            throw ModemCoordinatorError.selectedBackendNotRegistered(identity.kind)
        }
        return ActiveModem(
            identity: identity,
            endpoint: attempt.candidate.endpoint,
            capabilities: registration.backend.capabilities
        )
    }

    private func rankedMatches(
        in report: ModemDiscoveryReport,
        preferredScopeKey: String?
    ) -> [ModemDiscoveryAttempt] {
        report.matches.enumerated().sorted { lhs, rhs in
            let lhsManual = lhs.element.candidate.sources.contains(.manual)
            let rhsManual = rhs.element.candidate.sources.contains(.manual)
            if lhsManual != rhsManual { return lhsManual }
            let lhsPreferred = lhs.element.candidate.endpoint.scopeKey == preferredScopeKey
            let rhsPreferred = rhs.element.candidate.endpoint.scopeKey == preferredScopeKey
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            if lhs.element.candidate.priority != rhs.element.candidate.priority {
                return lhs.element.candidate.priority > rhs.element.candidate.priority
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func relevantIdentificationFailures(
        in report: ModemDiscoveryReport,
        includeAll: Bool
    ) -> [CoordinatedModemFailure] {
        let strongEvidence: Set<ModemDiscoveryCandidateSource> = [
            .matchingSubnet,
            .matchingGateway,
            .manual,
            .lastSuccessful
        ]
        var seen: Set<CoordinatedModemFailure> = []
        var failures: [CoordinatedModemFailure] = []
        for attempt in report.attempts {
            guard case let .failed(message, category) = attempt.result,
                  includeAll || !attempt.candidate.sources.isDisjoint(with: strongEvidence),
                  !message.isEmpty
            else { continue }
            let failure = CoordinatedModemFailure(
                kind: attempt.candidate.kind,
                category: category,
                message: message
            )
            guard seen.insert(failure).inserted else { continue }
            failures.append(failure)
        }
        return failures
    }

    private func structuredCoordinatorError(
        for failures: [CoordinatedModemFailure]
    ) -> ModemCoordinatorError? {
        for category in [ModemFailureCategory.authentication, .qmiUnavailable] {
            let matching = failures.filter { $0.category == category }
            guard !matching.isEmpty else { continue }
            let kinds = Set(matching.map(\.kind))
            let kind = kinds.count == 1 ? kinds.first : nil
            let messages = deduplicatedMessages(from: matching)
            switch category {
            case .authentication:
                return .authenticationFailed(kind: kind, messages: messages)
            case .qmiUnavailable:
                return .qmiUnavailable(kind: kind, messages: messages)
            case .other:
                break
            }
        }
        return nil
    }

    private func deduplicatedMessages(
        from failures: [CoordinatedModemFailure]
    ) -> [String] {
        var seen: Set<String> = []
        return failures.compactMap { failure in
            guard !failure.message.isEmpty,
                  seen.insert(failure.message).inserted
            else { return nil }
            return failure.message
        }
    }
}
