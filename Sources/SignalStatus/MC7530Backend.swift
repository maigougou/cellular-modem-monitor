import Foundation

/// Read-only adapter for the MC7530CA / G5 MAX Web UBus API.
///
/// Discovery is anonymous. The administrator credential is accepted only by
/// `fetchSnapshot`, retained in memory with its scoped session, and never
/// persisted or logged by this backend.
actor MC7530Backend: ModemStatusBackend {
    nonisolated let kind = ModemKind.zteMC7530CA
    nonisolated let capabilities: ModemCapability = [
        .statusRead,
        .identityRead,
        .webUI
    ]

    private struct CachedSession {
        let endpoint: ScopedEndpoint
        let credentials: WebCredentials
        let session: ZTEAuthSession
    }

    private let httpTransport: any ZTEHTTPTransport
    private var sessionsByScope: [String: CachedSession] = [:]
    private var activeCredentials: WebCredentials?
    private var credentialGeneration: UInt64 = 0
    private var credentialsValidated = false
    private var credentialsRejected = false
    private var credentialValidationTask: Task<Void, Error>?

    init(httpTransport: any ZTEHTTPTransport = NetworkBoundZTEHTTPTransport()) {
        self.httpTransport = httpTransport
    }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity? {
        _ = credentials
        let transport = try makeTransport(endpoint: endpoint)
        guard try await transport.hasMC7530Schema() else { return nil }
        return ModemIdentity(
            kind: kind,
            manufacturer: "ZTE",
            model: "MC7530CA",
            displayName: "ZTE MC7530CA / G5 MAX"
        )
    }

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot {
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
        let generation = try prepare(credentials: webCredentials)

        let transport = try makeTransport(endpoint: endpoint)
        let session = session(
            for: endpoint,
            credentials: webCredentials,
            transport: transport
        )
        do {
            try await validateCredentialsIfNeeded(
                session: session,
                credentials: webCredentials,
                generation: generation
            )
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                credentials: webCredentials,
                generation: generation
            )
            throw error
        }

        let payload: ZTEJSONValue
        do {
            payload = try await session.read(
                object: "zte_nwinfo_api",
                method: "nwinfo_get_netinfo"
            )
        } catch {
            rememberAuthenticationFailureIfCurrent(
                error,
                credentials: webCredentials,
                generation: generation
            )
            throw error
        }
        guard let host = endpoint.host else { throw ModemBackendError.invalidEndpoint }
        return try MC7530Parser.makeSnapshot(
            from: payload,
            host: host,
            interfaceName: endpoint.interfaceName
        )
    }

    private func makeTransport(endpoint: ScopedEndpoint) throws -> ZTEUBusTransport {
        guard endpoint.host != nil else { throw ModemBackendError.invalidEndpoint }
        return try ZTEUBusTransport(
            baseURL: endpoint.baseURL,
            route: ZTEHTTPRoute(
                interfaceName: endpoint.interfaceName,
                interfaceIndex: endpoint.interfaceIndex,
                // A routed target such as ZTE-behind-Slate may share an
                // interface with multiple IPv4 addresses. Pin the interface,
                // but let Network.framework choose the route's source address.
                sourceAddress: endpoint.connectionPath == .routed
                    ? nil
                    : endpoint.sourceAddress
            ),
            http: httpTransport
        )
    }

    private func prepare(credentials: WebCredentials) throws -> UInt64 {
        if activeCredentials != credentials {
            activeCredentials = credentials
            credentialGeneration &+= 1
            credentialsValidated = false
            credentialsRejected = false
            credentialValidationTask?.cancel()
            credentialValidationTask = nil
            sessionsByScope.removeAll()
        }
        guard !credentialsRejected else { throw ZTEUBusError.authenticationFailed }
        return credentialGeneration
    }

    private func validateCredentialsIfNeeded(
        session: ZTEAuthSession,
        credentials: WebCredentials,
        generation: UInt64
    ) async throws {
        guard activeCredentials == credentials,
              credentialGeneration == generation
        else { return }
        guard !credentialsRejected else { throw ZTEUBusError.authenticationFailed }
        guard !credentialsValidated else { return }

        let task: Task<Void, Error>
        if let credentialValidationTask {
            task = credentialValidationTask
        } else {
            task = Task { try await session.ensureAuthenticated() }
            credentialValidationTask = task
        }

        do {
            try await task.value
            if activeCredentials == credentials,
               credentialGeneration == generation {
                credentialsValidated = true
                credentialValidationTask = nil
            }
        } catch {
            if activeCredentials == credentials,
               credentialGeneration == generation {
                credentialValidationTask = nil
            }
            throw error
        }
    }

    private func rememberAuthenticationFailureIfCurrent(
        _ error: Error,
        credentials: WebCredentials,
        generation: UInt64
    ) {
        guard error as? ZTEUBusError == .authenticationFailed,
              activeCredentials == credentials,
              credentialGeneration == generation
        else { return }
        credentialsValidated = false
        credentialsRejected = true
        credentialValidationTask = nil
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
    ) -> ZTEAuthSession {
        if let cached = sessionsByScope[endpoint.scopeKey],
           cached.endpoint == endpoint,
           cached.credentials == credentials {
            return cached.session
        }

        let replacement = ZTEAuthSession(
            transport: transport,
            username: credentials.username,
            password: credentials.password
        )
        sessionsByScope[endpoint.scopeKey] = CachedSession(
            endpoint: endpoint,
            credentials: credentials,
            session: replacement
        )
        return replacement
    }
}
