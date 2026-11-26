import Foundation

public protocol T3Source: AnyObject, Sendable {
    func updates() async -> AsyncStream<ShellUpdate>
    func detail(threadId: String, in environment: String?) async throws -> ThreadProjection
    func send(_ command: T3Command, in environment: String?) async throws
    func linked() async -> ShellSnapshot
    func environmentId() async -> String?
    func providers() -> [ProviderLimits]
}

public final class LiveSource: T3Source {
    private let client: T3ServerClient
    private let limits: UsageLimitsReader

    public init(home: T3Home = T3Home(), tokenStore: TokenStore = FileTokenStore(),
                linkTokenStore: TokenStore = FileTokenStore(file: StateFolders.current.linkSession),
                clock: any T3Clock = LiveClock()) {
        let runner = ProcessRunner(clock: clock)
        let signIn = T3SignIn(home: home, store: tokenStore, runner: runner, clock: clock)
        let linkSignIn = T3SignIn(home: home, store: linkTokenStore, runner: runner,
                                  label: "\(StateFolders.appName()) links", subject: "mcp-client", clock: clock)
        client = T3ServerClient(home: home, signIn: signIn, linkSignIn: linkSignIn)
        limits = UsageLimitsReader(home: home)
    }

    public func updates() async -> AsyncStream<ShellUpdate> {
        await client.shellUpdates()
    }

    public func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        try await client.detail(threadId: threadId, in: environment)
    }

    public func send(_ command: T3Command, in environment: String?) async throws {
        try await client.dispatch(command, in: environment)
    }

    public func linked() async -> ShellSnapshot {
        await client.linkedSnapshot()
    }

    public func environmentId() async -> String? {
        await client.environment()
    }

    public func providers() -> [ProviderLimits] {
        limits.read()
    }
}
