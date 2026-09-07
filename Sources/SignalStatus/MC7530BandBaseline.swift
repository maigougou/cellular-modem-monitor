import Foundation

/// Bands observed from this physical modem, not a model-specific capability
/// whitelist. The bounds below are the masks' wire-representation limits.
struct MC7530BandMasks: Codable, Equatable, Sendable {
    let saBands: Set<Int>
    let nsaBands: Set<Int>
    let lteBands: Set<Int>

    var isValid: Bool {
        !saBands.isEmpty && !nsaBands.isEmpty && !lteBands.isEmpty &&
            saBands.allSatisfy { (1...512).contains($0) } &&
            nsaBands.allSatisfy { (1...512).contains($0) } &&
            lteBands.allSatisfy { (1...256).contains($0) }
    }

    func union(_ other: Self) -> Self {
        Self(
            saBands: saBands.union(other.saBands),
            nsaBands: nsaBands.union(other.nsaBands),
            lteBands: lteBands.union(other.lteBands)
        )
    }

    func isSubset(of other: Self) -> Bool {
        saBands.isSubset(of: other.saBands) &&
            nsaBands.isSubset(of: other.nsaBands) &&
            lteBands.isSubset(of: other.lteBands)
    }
}

/// `observed` is accumulated across successful device reads. `restore` is a
/// separately captured pre-lock state; neither value means factory defaults or
/// proves RF capability. There are deliberately no credentials or raw serials.
struct MC7530BandBaseline: Codable, Equatable, Sendable {
    var observed: MC7530BandMasks
    var restore: MC7530BandMasks?
    var capturedAt: Date
    var updatedAt: Date

    var isValid: Bool {
        observed.isValid &&
            capturedAt.timeIntervalSinceReferenceDate.isFinite &&
            updatedAt.timeIntervalSinceReferenceDate.isFinite &&
            updatedAt >= capturedAt &&
            (restore.map { $0.isValid && $0.isSubset(of: observed) } ?? true)
    }
}

enum MC7530BandBaselineStoreError: LocalizedError, Equatable, Sendable {
    case invalidFingerprint
    case invalidBaseline
    case invalidFormat
    case unsupportedSchemaVersion(Int)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .invalidFingerprint:
            return "The band baseline requires a verified modem fingerprint."
        case .invalidBaseline:
            return "The band baseline contains invalid or inconsistent band data."
        case .invalidFormat:
            return "The saved band baseline file is invalid. It was not overwritten."
        case .unsupportedSchemaVersion(let version):
            return "Band baseline schema version \(version) is not supported. The file was not overwritten."
        case .unsafePath(let path):
            return "The band baseline storage path is not a regular local file or directory: \(path)"
        }
    }
}

protocol MC7530BandBaselineStore: Sendable {
    func load(for fingerprint: String) throws -> MC7530BandBaseline?
    func save(_ baseline: MC7530BandBaseline, for fingerprint: String) throws
}

/// Test/session storage is intentionally instance-local; constructing a fresh
/// store must never inherit another physical modem's observations.
final class InMemoryMC7530BandBaselineStore: MC7530BandBaselineStore, @unchecked Sendable {
    private let lock = NSLock()
    private var baselines: [String: MC7530BandBaseline] = [:]

    init() {}

    init(baselines: [String: MC7530BandBaseline]) throws {
        try validateBandBaselines(baselines)
        self.baselines = baselines
    }

    func load(for fingerprint: String) throws -> MC7530BandBaseline? {
        try validateBandFingerprint(fingerprint)
        lock.lock()
        defer { lock.unlock() }
        return baselines[fingerprint]
    }

    func save(_ baseline: MC7530BandBaseline, for fingerprint: String) throws {
        try validateBandFingerprint(fingerprint)
        guard baseline.isValid else { throw MC7530BandBaselineStoreError.invalidBaseline }
        lock.lock()
        defer { lock.unlock() }
        baselines[fingerprint] = baseline
    }
}

/// Durable observations and pre-lock restore points keyed only by the SHA-256
/// physical-device fingerprint returned by MC7530ControlSession.fingerprint.
/// A corrupt/unknown store fails closed, including saves, so recovery data is
/// never silently replaced by an empty document.
final class FileMC7530BandBaselineStore: MC7530BandBaselineStore, @unchecked Sendable {
    static let shared = FileMC7530BandBaselineStore()
    static let directoryName = "Cellular Modem Monitor"
    static let fileName = "band-baselines.json"

    // Serialize the read-modify-write transaction across instances in this
    // process, including separately constructed sessions for the same modem.
    private static let lock = NSLock()
    private let fileURL: URL
    private let fileManager: FileManager

    private struct Document: Codable {
        let schemaVersion: Int
        var devices: [String: MC7530BandBaseline]
    }

    private struct Version: Decodable {
        let schemaVersion: Int
    }

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
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

    func load(for fingerprint: String) throws -> MC7530BandBaseline? {
        try validateBandFingerprint(fingerprint)
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try readDocument().devices[fingerprint]
    }

    func save(_ baseline: MC7530BandBaseline, for fingerprint: String) throws {
        try validateBandFingerprint(fingerprint)
        guard baseline.isValid else { throw MC7530BandBaselineStoreError.invalidBaseline }
        Self.lock.lock()
        defer { Self.lock.unlock() }
        // Validate every existing entry before modifying anything. An invalid
        // entry for another device is still important recovery evidence.
        var document = try readDocument()
        document.devices[fingerprint] = baseline
        try writeDocument(document)
    }

    private func readDocument() throws -> Document {
        try validateLocalURL()
        guard let attributes = try attributesIfPresent(at: fileURL) else {
            return Document(schemaVersion: 1, devices: [:])
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw MC7530BandBaselineStoreError.unsafePath(fileURL.path)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let document: Document
        do {
            // Inspect the version before decoding the payload, since a newer
            // schema may legitimately have a completely different structure.
            let version = try decoder.decode(Version.self, from: data).schemaVersion
            guard version == 1 else {
                throw MC7530BandBaselineStoreError.unsupportedSchemaVersion(version)
            }
            document = try decoder.decode(Document.self, from: data)
        } catch let error as MC7530BandBaselineStoreError {
            throw error
        } catch {
            throw MC7530BandBaselineStoreError.invalidFormat
        }
        try validateBandBaselines(document.devices)
        return document
    }

    private func writeDocument(_ document: Document) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if let attributes = try attributesIfPresent(at: directoryURL) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw MC7530BandBaselineStoreError.unsafePath(directoryURL.path)
            }
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func validateLocalURL() throws {
        guard fileURL.isFileURL, !fileURL.lastPathComponent.isEmpty,
              fileURL.path != "/"
        else { throw MC7530BandBaselineStoreError.unsafePath(fileURL.path) }
    }

    private func attributesIfPresent(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            // attributesOfItem uses the item's own type, so a dangling symbolic
            // link is rejected too instead of being treated as a missing file.
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return nil
        }
    }
}

private func validateBandFingerprint(_ fingerprint: String) throws {
    // This must track MC7530ControlSession.fingerprint's canonical lowercase
    // SHA-256 digest; reject generic host/model keys and raw device identifiers.
    guard fingerprint.utf8.count == 64,
          fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw MC7530BandBaselineStoreError.invalidFingerprint }
}

private func validateBandBaselines(_ baselines: [String: MC7530BandBaseline]) throws {
    for (fingerprint, baseline) in baselines {
        try validateBandFingerprint(fingerprint)
        guard baseline.isValid else { throw MC7530BandBaselineStoreError.invalidBaseline }
    }
}
