import Foundation
import Security

protocol CredentialStoring: Sendable {
    func password(for account: String) throws -> String?
    func setPassword(_ password: String, for account: String) throws
    func removePassword(for account: String) throws
}

enum CredentialStoreError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "The Keychain operation failed: \(message)"
            }
            return "The Keychain operation failed (\(status))."
        }
    }
}

struct CredentialUpdate: Equatable, Sendable {
    let account: String
    let password: String
}

/// Records whether the value shown in Settings came from a successful
/// Keychain read. An unavailable value is not equivalent to an empty value:
/// overwriting it with an empty field could delete a credential that still
/// exists in Keychain.
enum CredentialLoadState: Equatable, Sendable {
    case loaded(String)
    case unavailable(String)
}

struct CredentialLoadResult: Equatable, Sendable {
    let password: String
    let state: CredentialLoadState
}

struct CredentialEdit: Equatable, Sendable {
    let account: String
    let password: String
    let loadState: CredentialLoadState
}

enum CredentialSavePlanner {
    /// Emits only explicit edits. After a successful read, changing a value to
    /// empty is an intentional delete. After a failed read, an unchanged empty
    /// field is unknown and must be preserved; only a non-empty replacement is
    /// safe to write.
    static func updates(for edits: [CredentialEdit]) -> [CredentialUpdate] {
        edits.compactMap { edit in
            switch edit.loadState {
            case let .loaded(original):
                guard edit.password != original else { return nil }
            case .unavailable:
                guard !edit.password.isEmpty else { return nil }
            }
            return CredentialUpdate(account: edit.account, password: edit.password)
        }
    }
}

enum CredentialTransactionError: LocalizedError {
    case rollbackFailed(writeError: String, rollbackErrors: [String])

    var errorDescription: String? {
        switch self {
        case let .rollbackFailed(writeError, rollbackErrors):
            return "Keychain update failed (\(writeError)); restoring the previous credentials also failed: \(rollbackErrors.joined(separator: "; "))"
        }
    }
}

/// Keychain does not provide a transaction spanning independent generic
/// password items. Snapshot both values first and restore both if either write
/// fails, so Settings never reports a clean failure after a partial update.
enum CredentialTransaction {
    private enum OriginalCredential {
        case missing
        case value(String)
    }

    static func apply(
        _ updates: [CredentialUpdate],
        store: any CredentialStoring
    ) throws {
        var originals: [String: OriginalCredential] = [:]
        for update in updates where originals[update.account] == nil {
            if let password = try store.password(for: update.account) {
                originals[update.account] = .value(password)
            } else {
                originals[update.account] = .missing
            }
        }

        do {
            for update in updates {
                try store.setPassword(update.password, for: update.account)
            }
        } catch {
            let writeError = error
            var rollbackErrors: [String] = []
            for update in updates.reversed() {
                guard let original = originals[update.account] else { continue }
                do {
                    switch original {
                    case let .value(password):
                        try store.setPassword(password, for: update.account)
                    case .missing:
                        try store.removePassword(for: update.account)
                    }
                } catch {
                    rollbackErrors.append(error.localizedDescription)
                }
            }
            if !rollbackErrors.isEmpty {
                throw CredentialTransactionError.rollbackFailed(
                    writeError: writeError.localizedDescription,
                    rollbackErrors: rollbackErrors
                )
            }
            throw writeError
        }
    }
}

/// Stores modem credentials independently from discovery and radio data.
///
/// UserDefaults intentionally holds only non-secret connection preferences.
/// Passwords never become part of a management URL, diagnostics, or a modem
/// endpoint cache.
final class KeychainCredentialStore: CredentialStoring, @unchecked Sendable {
    static let shared = KeychainCredentialStore()

    private let service: String

    init(service: String = "com.maigougou.cellularmodemmonitor.credentials") {
        self.service = service
    }

    func password(for account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw CredentialStoreError.unexpectedStatus(errSecDecode)
        }
        return password
    }

    func setPassword(_ password: String, for account: String) throws {
        guard !password.isEmpty else {
            try removePassword(for: account)
            return
        }

        let data = Data(password.utf8)
        let query = baseQuery(account: account)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }
    }

    func removePassword(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}
