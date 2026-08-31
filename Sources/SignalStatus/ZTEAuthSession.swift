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

    /// Performs an authenticated read. If rpcd rejects a previously valid SID,
    /// the session is recreated once and the read is retried exactly once.
    func read(
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue] = [:]
    ) async throws -> ZTEJSONValue {
        let sid = try await currentSessionID()
        do {
            let first = try await transport.call(
                sessionID: sid,
                object: object,
                method: method,
                parameters: parameters
            )
            if first.status == 6 {
                return try await retryAfterSessionExpiry(
                    failedSessionID: sid,
                    object: object,
                    method: method,
                    parameters: parameters
                )
            }
            guard first.status == 0 else { throw ZTEUBusError.ubusStatus(first.status) }
            guard let payload = first.payload else { throw ZTEUBusError.invalidResponse }
            return payload
        } catch let error as ZTEUBusError where error.isAccessDenied {
            return try await retryAfterSessionExpiry(
                failedSessionID: sid,
                object: object,
                method: method,
                parameters: parameters
            )
        }
    }

    private func retryAfterSessionExpiry(
        failedSessionID: String,
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue]
    ) async throws -> ZTEJSONValue {
        let sid: String
        if let current = sessionID, current != failedSessionID {
            // Another read already refreshed this expired SID while the failed
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
                parameters: parameters
            )
        } catch let error as ZTEUBusError where error.isAccessDenied {
            if sessionID == sid { sessionID = nil }
            throw error
        }
        guard retry.status == 0 else {
            if retry.status == 6, sessionID == sid { sessionID = nil }
            throw ZTEUBusError.ubusStatus(retry.status)
        }
        guard let payload = retry.payload else { throw ZTEUBusError.invalidResponse }
        return payload
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
