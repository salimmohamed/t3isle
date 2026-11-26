import Foundation

public struct ReplayStatus: Codable, Equatable, Sendable {
    public let scenario: String
    public let finished: Bool

    public init(scenario: String, finished: Bool) {
        self.scenario = scenario
        self.finished = finished
    }
}

public enum ReplayProgress: Equatable, Sendable {
    case started(String, steps: Int)
    case finished(String)
}

public final class ReplaySource: T3Source, @unchecked Sendable {
    private let clock: any T3Clock
    private let lock = NSLock()
    private var world = ReplayWorld()
    private var subscribers: [UUID: AsyncStream<ShellUpdate>.Continuation] = [:]
    private var playback: Task<Void, Never>?
    private var generation = 0
    private var status: ReplayStatus?
    private var progressHandler: (@Sendable (ReplayProgress) -> Void)?

    public init(scenario: Scenario?, clock: any T3Clock = LiveClock()) {
        self.clock = clock
        if let scenario { play(scenario) }
    }

    public var current: ReplayStatus? { lock.withLock { status } }

    #if DEBUG
    public var threads: [ThreadShell] { lock.withLock { world.snapshot.threads } }
    #endif

    public func onProgress(_ handler: @escaping @Sendable (ReplayProgress) -> Void) {
        lock.withLock { progressHandler = handler }
    }

    public func play(_ scenario: Scenario) {
        let start = clock.now
        let schedule = (try? scenario.events(startingAt: start)) ?? []
        let (playing, handler) = lock.withLock {
            generation += 1
            playback?.cancel()
            playback = nil
            world = ReplayWorld()
            status = ReplayStatus(scenario: scenario.name, finished: false)
            broadcast(.snapshot(world.snapshot))
            return (generation, progressHandler)
        }
        handler?(.started(scenario.name, steps: scenario.stepCount))
        let task = Task { [weak self, clock] in
            var offset = Duration.zero
            for (after, event) in schedule {
                offset += after
                if after > .zero { try? await clock.sleep(until: start + offset / .seconds(1)) }
                guard self?.apply(event, playing) == true else { return }
            }
            self?.finish(scenario.name, playing)
        }
        lock.withLock {
            if generation == playing { playback = task } else { task.cancel() }
        }
    }

    public func stop() {
        lock.withLock {
            generation += 1
            playback?.cancel()
            playback = nil
            status = nil
        }
    }

    public func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.subscribers.removeValue(forKey: id) }
        }
        lock.withLock {
            subscribers[id] = continuation
            continuation.yield(.snapshot(world.snapshot))
        }
        return stream
    }

    public func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        guard let projection = lock.withLock({ world.projections[threadId] }) else {
            throw T3Failure.http(404, "Thread not found")
        }
        return projection
    }

    public func send(_ command: T3Command, in environment: String?) async throws {
        try lock.withLock {
            broadcast(try world.respond(to: command, at: clock.now))
        }
    }

    public func linked() async -> ShellSnapshot { ShellSnapshot(threads: [], projects: []) }

    public static let environment = "replay"

    public func environmentId() async -> String? { Self.environment }

    public func providers() -> [ProviderLimits] { lock.withLock { world.providers } }

    private func apply(_ event: ReplayEvent, _ playing: Int) -> Bool {
        lock.withLock {
            guard generation == playing else { return false }
            if let update = world.apply(event) { broadcast(update) }
            return true
        }
    }

    private func finish(_ name: String, _ playing: Int) {
        let handler: (@Sendable (ReplayProgress) -> Void)? = lock.withLock {
            guard generation == playing else { return nil }
            status = ReplayStatus(scenario: name, finished: true)
            return progressHandler
        }
        handler?(.finished(name))
    }

    private func broadcast(_ update: ShellUpdate) {
        for continuation in subscribers.values { continuation.yield(update) }
    }
}
