import Foundation
import Security

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

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.t3isle.app", account: String = "t3-server-session") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> StoredToken? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func save(_ token: StoredToken) throws {
        let data = try JSONEncoder().encode(token)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw T3Failure.keychain(added) }
        } else if status != errSecSuccess {
            throw T3Failure.keychain(status)
        }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
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
