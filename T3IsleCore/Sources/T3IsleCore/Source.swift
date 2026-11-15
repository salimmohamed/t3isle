import Foundation

public protocol T3Source: AnyObject, Sendable {
    func updates() async -> AsyncStream<ShellUpdate>
    func detail(threadId: String) async throws -> ThreadProjection
    func send(_ command: T3Command) async throws
    func environmentId() async -> String?
    func providers() -> [ProviderLimits]
    func signOut() async
}

public final class LiveSource: T3Source {
    private let client: T3ServerClient
    private let limits: UsageLimitsReader

    public init(home: T3Home = T3Home(), tokenStore: TokenStore = KeychainTokenStore()) {
        client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: tokenStore))
        limits = UsageLimitsReader(home: home)
    }

    public func updates() async -> AsyncStream<ShellUpdate> {
        await client.shellUpdates()
    }

    public func detail(threadId: String) async throws -> ThreadProjection {
        try await client.detail(threadId: threadId)
    }

    public func send(_ command: T3Command) async throws {
        try await client.dispatch(command)
    }

    public func environmentId() async -> String? {
        await client.environment()
    }

    public func providers() -> [ProviderLimits] {
        limits.read()
    }

    public func signOut() async {
        await client.signOut()
    }
}
