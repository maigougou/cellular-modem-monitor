import Foundation

protocol VOSStatusReading: Sendable {
    func fetchDeviceFingerprint(configuration: DeviceConfiguration) async throws -> String
    func fetchSnapshot(configuration: DeviceConfiguration) async throws -> DeviceSnapshot
}

extension VOSClient: VOSStatusReading {}

/// Adapts the existing SSH/QMI client to the transport-neutral status and
/// control backends.
actor VOSBackend: ModemControlBackend {
    nonisolated let kind = ModemKind.vos5G
    nonisolated let capabilities: ModemCapability

    private let client: any VOSStatusReading
    private let controlClient: VOSClient?
    /// One bad username/password must not be replayed against every interface
    /// candidate on every poll. A credential change clears the effective gate.
    private var rejectedCredentials: SSHCredentials?

    init(client: any VOSStatusReading = VOSClient()) {
        self.client = client
        self.controlClient = client as? VOSClient
        var capabilities: ModemCapability = [
            .radioStatus,
            .deviceInformation,
            .webUI
        ]
        if self.controlClient != nil { capabilities.formUnion(.vosControls) }
        self.capabilities = capabilities
    }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity? {
        let resolved = try makeConfiguration(endpoint: endpoint, credentials: credentials)
        try rejectPreviouslyFailed(resolved.credentials)
        do {
            let fingerprint = try await client.fetchDeviceFingerprint(configuration: resolved.configuration)
            rejectedCredentials = nil
            return ModemIdentity(
                kind: kind,
                manufacturer: "VOS",
                model: "VOS 5G",
                stableIdentifier: fingerprint
            )
        } catch {
            rememberAuthenticationFailure(error, credentials: resolved.credentials)
            throw error
        }
    }

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot {
        let resolved = try makeConfiguration(endpoint: endpoint, credentials: credentials)
        try rejectPreviouslyFailed(resolved.credentials)
        do {
            let snapshot = try await client.fetchSnapshot(configuration: resolved.configuration)
            rejectedCredentials = nil
            return snapshot
        } catch {
            rememberAuthenticationFailure(error, credentials: resolved.credentials)
            throw error
        }
    }

    func openControlSession(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> any ModemControlSession {
        guard let controlClient else {
            throw ModemBackendError.unsupportedCapability(.deviceControls)
        }
        let resolved = try makeConfiguration(endpoint: endpoint, credentials: credentials)
        try rejectPreviouslyFailed(resolved.credentials)
        do {
            let session = try await VOSControlSession.open(
                client: controlClient,
                configuration: resolved.configuration
            )
            rejectedCredentials = nil
            return session
        } catch {
            rememberAuthenticationFailure(error, credentials: resolved.credentials)
            throw error
        }
    }

    private func makeConfiguration(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) throws -> (configuration: DeviceConfiguration, credentials: SSHCredentials) {
        guard endpoint.host != nil else { throw ModemBackendError.invalidEndpoint }
        guard case let .ssh(ssh) = credentials else {
            if credentials == .none {
                throw ModemBackendError.credentialsRequired(.ssh)
            }
            throw ModemBackendError.incompatibleCredentials(expected: .ssh, actual: credentials.kind)
        }
        return (
            DeviceConfiguration(
                host: endpoint.baseURL.absoluteString,
                username: ssh.username,
                password: ssh.password,
                refreshInterval: 30,
                sourceAddress: endpoint.sourceAddress,
                interfaceName: endpoint.interfaceName
            ),
            ssh
        )
    }

    private func rejectPreviouslyFailed(_ credentials: SSHCredentials) throws {
        if rejectedCredentials == credentials {
            throw VOSClientError.authenticationFailed
        }
    }

    private func rememberAuthenticationFailure(
        _ error: Error,
        credentials: SSHCredentials
    ) {
        if error as? VOSClientError == .authenticationFailed {
            rejectedCredentials = credentials
        }
    }
}
