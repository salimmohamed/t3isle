import Foundation
@testable import T3IsleCore

extension RpcSocket {
    static let pingsBeforeTimeout = Int(pongTimeout / pingInterval)

    var pingLoop: Task<Void, Never>? {
        Mirror(reflecting: self).descendant("pings") as? Task<Void, Never>
    }
}

extension T3ServerClient {
    func openSocket() async throws -> RpcSocket? {
        let fields = Mirror(reflecting: self)
        if let socket = fields.descendant("socket") as? RpcSocket { return socket }
        return try await (fields.descendant("connecting") as? Task<RpcSocket, Error>)?.value
    }
}

enum PingEvent: Equatable {
    case sent(String)
    case closed(T3Failure)
    case asleep(for: TimeInterval)
    case pingsStopped
    case noPingLoop
}

final class PingWatch: @unchecked Sendable {
    let clock = TestClock()
    let recordingClock: any T3Clock
    private let recorded: AsyncStream<PingEvent>.Continuation
    private var events: AsyncStream<PingEvent>.Iterator
    private var pendingRest: PingEvent?
    private var ended: PingEvent?

    init() {
        let (events, recorded) = AsyncStream.makeStream(of: PingEvent.self)
        self.events = events.makeAsyncIterator()
        self.recorded = recorded
        recordingClock = SleepRecordingClock(clock) { recorded.yield(.asleep(for: $0)) }
    }

    func record(_ event: PingEvent) {
        recorded.yield(event)
    }

    func watch(_ socket: RpcSocket) {
        let recorded = recorded
        guard let loop = socket.pingLoop else {
            recorded.yield(.noPingLoop)
            return
        }
        Task {
            await loop.value
            recorded.yield(.pingsStopped)
        }
    }

    func tick() async -> PingEvent? {
        let rest = await untilAsleep()
        guard rest == .asleep(for: RpcSocket.pingInterval) else { return rest }
        pendingRest = nil
        await clock.waitForSleepers()
        clock.advance(by: RpcSocket.pingInterval)
        return await nextNotingRest()
    }

    func untilAsleep() async -> PingEvent? {
        if let pendingRest { return pendingRest }
        return await nextNotingRest()
    }

    private func nextNotingRest() async -> PingEvent? {
        let event = await next()
        if case .asleep = event { pendingRest = event }
        return event
    }

    private func next() async -> PingEvent? {
        if let ended { return ended }
        let event = await events.next()
        if event == .pingsStopped || event == .noPingLoop { ended = event }
        return event
    }
}

private final class SleepRecordingClock: T3Clock, @unchecked Sendable {
    private let base: TestClock
    private let asleep: @Sendable (TimeInterval) -> Void

    init(_ base: TestClock, asleep: @escaping @Sendable (TimeInterval) -> Void) {
        self.base = base
        self.asleep = asleep
    }

    var now: Date { base.now }

    func sleep(until deadline: Date) async throws {
        asleep(deadline.timeIntervalSince(base.now))
        try await base.sleep(until: deadline)
    }
}
