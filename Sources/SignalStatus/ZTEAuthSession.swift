import CryptoKit
import Foundation

/// Holds only an in-memory rpcd session. Credentials are supplied by the
/// caller; this type never reads a password from disk or embeds a device
/// credential.
actor ZTEAuthSession {
    private let transport: ZTEUBusTransport
    private let username: String?
    private let password: String
    private var sessionID: String?
    private var authenticationRejected = false
    private var loginTask: Task<String, Error>?

    init(transport: ZTEUBusTransport, username: String? = nil, password: String) {
        self.transport = transport
        let normalizedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = normalizedUsername?.isEmpty == false ? normalizedUsername : nil
        self.password = password
    }

    func invalidate() {
        sessionID = nil
    }

    func ensureAuthenticated() async throws {
        _ = try await currentSessionID()
    }

    /// Lifecycle writes deliberately bypass SID recovery/replay. Even a lost
    /// reply must not cause a second reboot request.
    func restartDevice() async throws {
        let sid = try await currentSessionID()
        try Task.checkCancellation()
        let result: ZTEUBusCallResult
        do {
            result = try await transport.call(
                sessionID: sid,
                object: "zwrt_mc.device.manager",
                method: "device_reboot",
                parameters: ["moduleName": .string("web")],
                mode: .read,
                zTag: ""
            )
        } catch let error as ZTEUBusError where error.isAccessDenied {
            throw error
        } catch {
            throw ModemRestartError.outcomeUnknown
        }
        guard result.status == 0 else { throw ZTEUBusError.ubusStatus(result.status) }
        sessionID = nil
    }

    /// Performs an authenticated read. This compatibility wrapper keeps the
    /// original read-only request headers and delegates session recovery to the
    /// generic call path.
    func read(
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue] = [:]
    ) async throws -> ZTEJSONValue {
        try await call(
            object: object,
            method: method,
            parameters: parameters,
            mode: .read
        )
    }

    /// Performs a payload-bearing authenticated UBus call. Read and polling
    /// callers require that payload; generic transports may also use this for
    /// actions whose firmware contract includes one. If rpcd rejects a
    /// previously valid SID, the session is recreated once and the identical
    /// call is retried exactly once.
    func call(
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue] = [:],
        mode: ZTEUBusCallMode = .read,
        zTag: String = ""
    ) async throws -> ZTEJSONValue {
        let result = try await authenticatedCall(
            object: object,
            method: method,
            parameters: parameters,
            mode: mode,
            zTag: zTag
        )
        guard let payload = result.payload else { throw ZTEUBusError.invalidResponse }
        return payload
    }

    /// Performs an authenticated action. UBus status zero is authoritative
    /// success even when the firmware returns the valid payload-free `[0]`
    /// result used by MC7530CA setters.
    func action(
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue] = [:],
        mode: ZTEUBusCallMode = .read,
        zTag: String = ""
    ) async throws {
        _ = try await authenticatedCall(
            object: object,
            method: method,
            parameters: parameters,
            mode: mode,
            zTag: zTag
        )
    }

    private func authenticatedCall(
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue],
        mode: ZTEUBusCallMode,
        zTag: String
    ) async throws -> ZTEUBusCallResult {
        let sid = try await currentSessionID()
        let first: ZTEUBusCallResult
        do {
            first = try await transport.call(
                sessionID: sid,
                object: object,
                method: method,
                parameters: parameters,
                mode: mode,
                zTag: zTag
            )
        } catch let error as ZTEUBusError where error.isAccessDenied {
            return try await retryAfterSessionExpiry(
                failedSessionID: sid,
                object: object,
                method: method,
                parameters: parameters,
                mode: mode,
                zTag: zTag
            )
        }
        // Keep this retry outside the do/catch above. If the replacement SID is
        // itself denied, that error must escape rather than being caught as a
        // second expiry and causing a third login/write attempt.
        if first.status == 6 {
            return try await retryAfterSessionExpiry(
                failedSessionID: sid,
                object: object,
                method: method,
                parameters: parameters,
                mode: mode,
                zTag: zTag
            )
        }
        guard first.status == 0 else { throw ZTEUBusError.ubusStatus(first.status) }
        return first
    }

    private func retryAfterSessionExpiry(
        failedSessionID: String,
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue],
        mode: ZTEUBusCallMode,
        zTag: String
    ) async throws -> ZTEUBusCallResult {
        let sid: String
        if let current = sessionID, current != failedSessionID {
            // Another call already refreshed this expired SID while the failed
            // request was in flight. Reuse that replacement instead of logging
            // in a second time and invalidating a newly valid session.
            sid = current
        } else {
            if sessionID == failedSessionID { sessionID = nil }
            sid = try await login()
        }
        let retry: ZTEUBusCallResult
        do {
            retry = try await transport.call(
                sessionID: sid,
                object: object,
                method: method,
                parameters: parameters,
                mode: mode,
                zTag: zTag
            )
        } catch let error as ZTEUBusError where error.isAccessDenied {
            if sessionID == sid { sessionID = nil }
            throw error
        }
        guard retry.status == 0 else {
            if retry.status == 6, sessionID == sid { sessionID = nil }
            throw ZTEUBusError.ubusStatus(retry.status)
        }
        return retry
    }

    private func currentSessionID() async throws -> String {
        guard !authenticationRejected else { throw ZTEUBusError.authenticationFailed }
        if let sessionID { return sessionID }
        return try await login()
    }

    private func login() async throws -> String {
        guard !authenticationRejected else { throw ZTEUBusError.authenticationFailed }
        if let loginTask {
            return try await completeLogin(loginTask)
        }

        let task = Task { try await performLogin() }
        loginTask = task
        return try await completeLogin(task)
    }

    private func completeLogin(_ task: Task<String, Error>) async throws -> String {
        do {
            let sid = try await task.value
            sessionID = sid
            loginTask = nil
            return sid
        } catch {
            loginTask = nil
            if error as? ZTEUBusError == .authenticationFailed {
                authenticationRejected = true
            }
            throw error
        }
    }

    private func performLogin() async throws -> String {
        let challenge = try await transport.call(
            sessionID: ZTEUBusTransport.zeroSessionID,
            object: "zwrt_web",
            method: "web_login_info"
        )
        guard challenge.status == 0 else { throw ZTEUBusError.ubusStatus(challenge.status) }
        guard let salt = challenge.object?["zte_web_sault"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !salt.isEmpty
        else { throw ZTEUBusError.missingSalt }

        var parameters: [String: ZTEJSONValue] = [
            "password": .string(Self.loginHash(password: password, salt: salt))
        ]
        if let username { parameters["username"] = .string(username) }

        let login = try await transport.call(
            sessionID: ZTEUBusTransport.zeroSessionID,
            object: "zwrt_web",
            method: "web_login",
            parameters: parameters
        )
        guard login.status == 0 else {
            throw ZTEUBusError.authenticationFailed
        }
        if let result = login.object?["result"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           result != "0" {
            throw ZTEUBusError.authenticationFailed
        }
        guard let sid = login.object?["ubus_rpc_session"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !sid.isEmpty
        else {
            throw ZTEUBusError.authenticationFailed
        }
        return sid
    }

    static func loginHash(password: String, salt: String) -> String {
        let first = uppercaseSHA256(password)
        return uppercaseSHA256(first + salt)
    }

    private static func uppercaseSHA256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }
}
