import Foundation

protocol CredentialStoring: Sendable {
    func password(for account: String) throws -> String?
    func setPassword(_ password: String, for account: String) throws
    func removePassword(for account: String) throws
}

enum LocalCredentialStoreError: LocalizedError, Equatable {
    case unsafePath(String)
    case invalidFormat
    case writeFailed

    var errorDescription: String? {
        switch self {
        case let .unsafePath(path):
            return "The local credential path is not a regular private file: \(path)"
        case .invalidFormat:
            return "The local credential file is unreadable or has an invalid format."
        case .writeFailed:
            return "The local credential file could not be written."
        }
    }
}

struct CredentialUpdate: Equatable, Sendable {
    let account: String
    let password: String
}

/// Records whether the value shown in Settings came from a successful local
/// credential-file read. An unavailable value is not equivalent to an empty
/// value: overwriting it could delete a credential that still exists on disk.
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
            return "Credential update failed (\(writeError)); restoring the previous credentials also failed: \(rollbackErrors.joined(separator: "; "))"
        }
    }
}

/// Snapshot both values first and restore both if either write fails, so
/// Settings never reports a clean failure after a partial update.
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

/// Stores modem credentials independently from discovery and radio data in a
/// single app-local JSON file.
///
/// The containing directory is 0700 and the file is 0600. This deliberately
/// avoids macOS Keychain prompts for a locally managed modem, but it is not
/// encrypted: software running as the same macOS account can read it.
final class LocalCredentialStore: CredentialStoring, @unchecked Sendable {
    static let shared = LocalCredentialStore()

    static let directoryName = "Cellular Modem Monitor"
    static let fileName = "credentials.json"

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func password(for account: String) throws -> String? {
        try withLock { try load()[account] }
    }

    func setPassword(_ password: String, for account: String) throws {
        guard !password.isEmpty else {
            try removePassword(for: account)
            return
        }

        try withLock {
            var values = try load()
            values[account] = password
            try save(values)
        }
    }

    func removePassword(for account: String) throws {
        try withLock {
            var values = try load()
            guard values.removeValue(forKey: account) != nil else { return }
            try save(values)
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func load() throws -> [String: String] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        // Restore both documented permission boundaries before reading an
        // existing store, even if they were changed outside the app.
        try ensurePrivateDirectory(fileURL.deletingLastPathComponent())
        let values = try fileURL.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isRegularFileKey
        ])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw LocalCredentialStoreError.unsafePath(fileURL.path)
        }
        // Tighten files created by an older build before reading them.
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw LocalCredentialStoreError.invalidFormat
        }
    }

    private func save(_ values: [String: String]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(directoryURL)

        if fileManager.fileExists(atPath: fileURL.path) {
            let resourceValues = try fileURL.resourceValues(forKeys: [
                .isSymbolicLinkKey,
                .isRegularFileKey
            ])
            guard resourceValues.isSymbolicLink != true,
                  resourceValues.isRegularFile == true
            else { throw LocalCredentialStoreError.unsafePath(fileURL.path) }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(values)
        do {
            // Atomic replacement occurs inside the private 0700 directory;
            // chmod the final inode before returning success.
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch let error as LocalCredentialStoreError {
            throw error
        } catch {
            throw LocalCredentialStoreError.writeFailed
        }
    }

    private func ensurePrivateDirectory(_ directoryURL: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            let values = try directoryURL.resourceValues(forKeys: [
                .isSymbolicLinkKey,
                .isDirectoryKey
            ])
            guard isDirectory.boolValue,
                  values.isSymbolicLink != true,
                  values.isDirectory == true
            else { throw LocalCredentialStoreError.unsafePath(directoryURL.path) }
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }
}
