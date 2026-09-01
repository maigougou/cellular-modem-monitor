import Foundation

/// Authenticated status and control adapter for the MC7530CA / G5 MAX Web
/// UBus API.
///
/// Discovery performs only schema/model preflight anonymously. Once those
/// fields identify this product family, the administrator credential is used
/// to fetch the device-unique identity and is retained only with its scoped
/// authenticated session; this backend never persists or logs it.
actor MC7530Backend: ModemControlBackend {
    nonisolated let kind = ModemKind.zteMC7530CA
    nonisolated let capabilities: ModemCapability = [
        .statusRead,
        .identityRead,
        .webUI,
        .operatorSelection,
        .networkScan,
        .radioAccessPreference,
        .nrBandLock,
        .lteBandLock
    ]

    private struct CachedSession: Sendable {
        let token: UUID
        let endpoint: ScopedEndpoint
        let credentials: WebCredentials
        let session: ZTEAuthSession
        var credentialsValidated: Bool
        var credentialsRejected: Bool
        var credentialValidationTask: Task<Void, Error>?
    }

    private let httpTransport: any ZTEHTTPTransport
    private var sessionsByScope: [String: CachedSession] = [:]

    private static let requiredModelPrefix = "MC7530CA"

    init(httpTransport: any ZTEHTTPTransport = NetworkBoundZTEHTTPTransport()) {
        self.httpTransport = httpTransport
    }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity? {
        let transport = try makeTransport(endpoint: endpoint)
        guard try await transport.hasMC7530Schema() else { return nil }
        let modelReply = try await transport.call(
            sessionID: ZTEUBusTransport.zeroSessionID,
            object: "uci",
            method: "get",
            parameters: [
                "config": .string("zwrt_common_info"),
                "section": .string("common_config")
            ],
            mode: .read,
            zTag: "zwrt_common_info"
        )
        guard modelReply.status == 0,
              let modelPayload = modelReply.payload,
              let reportedModel = try? Self.reportedModel(from: modelPayload),
              reportedModel.uppercased().hasPrefix(Self.requiredModelPrefix)
        else { return nil }

        // This retail firmware exposes its model anonymously but not the
        // device-unique modem_msn field. Authenticate only after the anonymous
        // schema/model checks, then use the same verified identity method that
        // protects every persistent control session.
        let context = try await authenticatedSession(
            endpoint: endpoint,
            credentials: credentials
        )
        do {
            try await validateTargetModel(session: context.session)
            let fingerprint = try await MC7530ControlSession.fetchFingerprint(
                session: context.session
            )
            return ModemIdentity(
                kind: kind,
                manufacturer: "ZTE",
                model: "MC7530CA",
                displayName: "ZTE MC7530CA / G5 MAX",
                stableIdentifier: fingerprint
            )
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                scopeKey: context.scopeKey,
                token: context.token
            )
            throw error
        }
    }

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot {
        let context = try await authenticatedSession(
            endpoint: endpoint,
            credentials: credentials
        )
        do {
            try await validateTargetModel(session: context.session)
            let payload = try await context.session.read(
                object: "zte_nwinfo_api",
                method: "nwinfo_get_netinfo"
            )
            guard let host = endpoint.host else { throw ModemBackendError.invalidEndpoint }
            return try MC7530Parser.makeSnapshot(
                from: payload,
                host: host,
                interfaceName: endpoint.interfaceName
            )
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                scopeKey: context.scopeKey,
                token: context.token
            )
            throw error
        }
    }

    func openControlSession(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> any ModemControlSession {
        let context = try await authenticatedSession(
            endpoint: endpoint,
            credentials: credentials
        )
        do {
            try await validateTargetModel(session: context.session)
            return try await MC7530ControlSession.open(session: context.session)
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                scopeKey: context.scopeKey,
                token: context.token
            )
            throw error
        }
    }

    private struct AuthenticatedContext {
        let session: ZTEAuthSession
        let scopeKey: String
        let token: UUID
    }

    /// The anonymous nwinfo object exists on several ZTE generations. Before
    /// status capabilities or any MC7530-specific write session are exposed,
    /// require the authenticated product identity used by this retail Web UI.
    private func validateTargetModel(session: ZTEAuthSession) async throws {
        let payload = try await session.call(
            object: "uci",
            method: "get",
            parameters: [
                "config": .string("zwrt_common_info"),
                "section": .string("common_config")
            ],
            mode: .read,
            zTag: "zwrt_common_info"
        )
        let reported = try Self.reportedModel(from: payload)
        guard reported.uppercased().hasPrefix(Self.requiredModelPrefix) else {
            throw ModemBackendError.deviceModelMismatch(
                expected: Self.requiredModelPrefix,
                actual: reported
            )
        }
    }

    private static func reportedModel(from payload: ZTEJSONValue) throws -> String {
        guard let reported = payload["values"]?["wa_inner_version"]?.stringValue?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !reported.isEmpty
        else { throw ModemBackendError.identityUnavailable }
        return reported
    }

    private func authenticatedSession(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> AuthenticatedContext {
        let suppliedCredentials: WebCredentials
        switch credentials {
        case let .web(value):
            suppliedCredentials = value
        case .none:
            throw ModemBackendError.credentialsRequired(.web)
        default:
            throw ModemBackendError.incompatibleCredentials(
                expected: .web,
                actual: credentials.kind
            )
        }
        let webCredentials = Self.normalized(suppliedCredentials)

        let transport = try makeTransport(endpoint: endpoint)
        let cached = session(
            for: endpoint,
            credentials: webCredentials,
            transport: transport
        )
        do {
            try await validateCredentialsIfNeeded(
                scopeKey: endpoint.scopeKey,
                token: cached.token,
                session: cached.session
            )
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                scopeKey: endpoint.scopeKey,
                token: cached.token
            )
            throw error
        }
        return AuthenticatedContext(
            session: cached.session,
            scopeKey: endpoint.scopeKey,
            token: cached.token
        )
    }

    private func makeTransport(endpoint: ScopedEndpoint) throws -> ZTEUBusTransport {
        guard endpoint.host != nil else { throw ModemBackendError.invalidEndpoint }
        return try ZTEUBusTransport(
            baseURL: endpoint.baseURL,
            route: ZTEHTTPRoute(
                interfaceName: endpoint.interfaceName,
                interfaceIndex: endpoint.interfaceIndex,
                // A routed target such as ZTE behind another router may share an
                // interface with multiple IPv4 addresses. Pin the interface,
                // but let Network.framework choose the route's source address.
                sourceAddress: endpoint.connectionPath == .routed
                    ? nil
                    : endpoint.sourceAddress
            ),
            http: httpTransport
        )
    }

    private func validateCredentialsIfNeeded(
        scopeKey: String,
        token: UUID,
        session: ZTEAuthSession,
    ) async throws {
        guard var cached = sessionsByScope[scopeKey], cached.token == token else {
            throw CancellationError()
        }
        guard !cached.credentialsRejected else { throw ZTEUBusError.authenticationFailed }
        guard !cached.credentialsValidated else { return }

        let task: Task<Void, Error>
        if let credentialValidationTask = cached.credentialValidationTask {
            task = credentialValidationTask
        } else {
            task = Task { try await session.ensureAuthenticated() }
            cached.credentialValidationTask = task
            sessionsByScope[scopeKey] = cached
        }

        do {
            try await task.value
            guard var current = sessionsByScope[scopeKey], current.token == token else {
                throw CancellationError()
            }
            current.credentialsValidated = true
            current.credentialValidationTask = nil
            sessionsByScope[scopeKey] = current
        } catch {
            if var current = sessionsByScope[scopeKey], current.token == token {
                current.credentialValidationTask = nil
                sessionsByScope[scopeKey] = current
            }
            throw error
        }
    }

    private func rememberAuthenticationFailureIfCurrent(
        _ error: Error,
        scopeKey: String,
        token: UUID
    ) {
        guard error as? ZTEUBusError == .authenticationFailed,
              var cached = sessionsByScope[scopeKey],
              cached.token == token
        else { return }
        cached.credentialsValidated = false
        cached.credentialsRejected = true
        cached.credentialValidationTask = nil
        sessionsByScope[scopeKey] = cached
    }

    private static func normalized(_ credentials: WebCredentials) -> WebCredentials {
        let candidate = credentials.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebCredentials(
            username: candidate?.isEmpty == false ? candidate : nil,
            password: credentials.password
        )
    }

    private func session(
        for endpoint: ScopedEndpoint,
        credentials: WebCredentials,
        transport: ZTEUBusTransport
    ) -> CachedSession {
        if let cached = sessionsByScope[endpoint.scopeKey],
           cached.endpoint == endpoint,
           cached.credentials == credentials {
            return cached
        }

        sessionsByScope[endpoint.scopeKey]?.credentialValidationTask?.cancel()
        let replacement = ZTEAuthSession(
            transport: transport,
            username: credentials.username,
            password: credentials.password
        )
        let cached = CachedSession(
            token: UUID(),
            endpoint: endpoint,
            credentials: credentials,
            session: replacement,
            credentialsValidated: false,
            credentialsRejected: false,
            credentialValidationTask: nil
        )
        sessionsByScope[endpoint.scopeKey] = cached
        return cached
    }
}
