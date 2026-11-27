import Foundation
import XCTest
@testable import T3IsleCore

final class RpcSocketPingTests: XCTestCase {
    private let ping = #"{"_tag":"Ping"}"#
    private let pong = #"{"_tag":"Pong"}"#
    private let pingsBeforeTimeout = Int(RpcSocket.pongTimeout / RpcSocket.pingInterval)

    func testMissingPongPastTheTimeoutClosesTheSocket() async {
        let harness = Harness()
        var sent = harness.transport.sent.makeAsyncIterator()
        var closes = harness.closes.makeAsyncIterator()

        for _ in 0..<pingsBeforeTimeout {
            await harness.tick()
            let sentPing = await sent.next()
            XCTAssertEqual(sentPing, ping)
        }
        XCTAssertFalse(harness.socket.isClosed)

        await harness.tick()
        let failure = await closes.next()
        XCTAssertEqual(failure, .notRunning)
        XCTAssertTrue(harness.socket.isClosed)
        XCTAssertTrue(harness.transport.isClosed)
        XCTAssertEqual(harness.transport.sentCount, pingsBeforeTimeout)
    }

    func testPongInTimeKeepsTheSocketOpen() async {
        let harness = Harness()
        var sent = harness.transport.sent.makeAsyncIterator()

        await harness.tick()
        let firstPing = await sent.next()
        XCTAssertEqual(firstPing, ping)
        harness.transport.deliver(pong)

        for _ in 0..<pingsBeforeTimeout {
            await harness.tick()
            let sentPing = await sent.next()
            XCTAssertEqual(sentPing, ping)
        }

        await harness.clock.waitForSleepers()
        XCTAssertFalse(harness.socket.isClosed)
        XCTAssertEqual(harness.closeCount, 0)
        harness.socket.close()
    }

    func testLatePongAfterTheCloseDoesNothing() async {
        let harness = Harness()
        var closes = harness.closes.makeAsyncIterator()
        for _ in 0...pingsBeforeTimeout { await harness.tick() }
        _ = await closes.next()
        let sentAtClose = harness.transport.sentCount
        let receivesAtClose = harness.transport.receiveCount

        harness.transport.deliver(pong)
        harness.clock.advance(by: RpcSocket.pongTimeout * 3)

        XCTAssertTrue(harness.socket.isClosed)
        XCTAssertEqual(harness.closeCount, 1)
        XCTAssertEqual(harness.transport.sentCount, sentAtClose)
        XCTAssertEqual(harness.transport.receiveCount, receivesAtClose)
        XCTAssertTrue(harness.clock.deadlines.isEmpty)
    }
}

private final class Harness: @unchecked Sendable {
    let clock = TestClock()
    let transport = FakeTransport()
    let socket: RpcSocket
    let closes: AsyncStream<T3Failure>
    private let closeContinuation: AsyncStream<T3Failure>.Continuation
    private let lock = NSLock()
    private var closed = 0

    init() {
        socket = RpcSocket(clock: clock)
        (closes, closeContinuation) = AsyncStream.makeStream(of: T3Failure.self)
        socket.open(transport) { [self] failure in
            lock.withLock { closed += 1 }
            closeContinuation.yield(failure)
        }
    }

    var closeCount: Int { lock.withLock { closed } }

    func tick() async {
        await clock.waitForSleepers()
        clock.advance(by: RpcSocket.pingInterval)
    }
}

private final class FakeTransport: RpcTransport, @unchecked Sendable {
    typealias Receiver = @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void

    let sent: AsyncStream<String>
    private let sentContinuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var receiver: Receiver?
    private var sends = 0
    private var receives = 0
    private var closed = false

    init() {
        (sent, sentContinuation) = AsyncStream.makeStream(of: String.self)
    }

    var sentCount: Int { lock.withLock { sends } }
    var receiveCount: Int { lock.withLock { receives } }
    var isClosed: Bool { lock.withLock { closed } }

    func resume() {}

    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { sends += 1 }
        sentContinuation.yield(text)
        completion(nil)
    }

    func receive(completion: @escaping Receiver) {
        lock.withLock {
            receives += 1
            receiver = completion
        }
    }

    func close() {
        lock.withLock { closed = true }
    }

    func deliver(_ text: String) {
        let receiver = lock.withLock {
            defer { self.receiver = nil }
            return self.receiver
        }
        receiver?(.success(.string(text)))
    }
}
