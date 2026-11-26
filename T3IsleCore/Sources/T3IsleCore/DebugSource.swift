#if DEBUG
import Foundation

public final class DebugSource: T3Source, @unchecked Sendable {
    public let base: T3Source
    public let replay: ReplaySource
    private let lock = NSLock()
    private var replaying = false

    public init(base: T3Source, clock: any T3Clock = LiveClock()) {
        self.base = base
        replay = ReplaySource(scenario: nil, clock: clock)
    }

    public var isReplaying: Bool { lock.withLock { replaying } }

    public func play(_ scenario: Scenario) {
        replay.play(scenario)
        lock.withLock { replaying = true }
    }

    public func stopReplay() {
        lock.withLock { replaying = false }
        replay.stop()
    }

    private var active: T3Source { lock.withLock { replaying ? replay : base } }

    public func updates() async -> AsyncStream<ShellUpdate> { await active.updates() }

    public func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        try await active.detail(threadId: threadId, in: environment)
    }

    public func send(_ command: T3Command, in environment: String?) async throws { try await active.send(command, in: environment) }

    public func linked() async -> ShellSnapshot { await active.linked() }

    public func environmentId() async -> String? { await active.environmentId() }

    public func providers() -> [ProviderLimits] { active.providers() }
}
#endif
