import Foundation

public struct StoredToken: Codable, Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    public let sessionId: String?

    public init(token: String, expiresAt: Date, sessionId: String? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.sessionId = sessionId
    }

    public func isUsable(at now: Date = Date()) -> Bool {
        expiresAt > now.addingTimeInterval(60)
    }
}

public protocol TokenStore: Sendable {
    func load() -> StoredToken?
    func save(_ token: StoredToken) throws
    func clear()
}

public struct FileTokenStore: TokenStore {
    private let file: URL

    public init(file: URL = FileTokenStore.defaultFile()) {
        self.file = file
    }

    public static func defaultFile() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3 Isle", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    public func load() -> StoredToken? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func save(_ token: StoredToken) throws {
        do {
            try write(JSONEncoder().encode(token))
        } catch {
            throw T3Failure.sessionNotSaved
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    private func write(_ data: Data) throws {
        let manager = FileManager.default
        let folder = file.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let staged = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: staged.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(staged.path, file.path) == 0 else {
            try? manager.removeItem(at: staged)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: StoredToken?

    public init(_ token: StoredToken? = nil) {
        self.token = token
    }

    public func load() -> StoredToken? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    public func save(_ token: StoredToken) throws {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}
