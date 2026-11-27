import Foundation
import XCTest
@testable import T3IsleCore

final class RpcSocketPingTests: XCTestCase {
    private let ping = PingEvent.sent(#"{"_tag":"Ping"}"#)
    private let pong = #"{"_tag":"Pong"}"#
    private let closed = PingEvent.closed(.notRunning)

    func testMissingPongPastTheTimeoutClosesTheSocket() async {
        let harness = Harness()
        for _ in 0..<RpcSocket.pingsBeforeTimeout {
            let event = await harness.tick()
            XCTAssertEqual(event, ping)
        }
        XCTAssertFalse(harness.socket.isClosed)

        let event = await harness.tick()
        XCTAssertEqual(event, closed)
        XCTAssertTrue(harness.socket.isClosed)
        XCTAssertTrue(harness.transport.isClosed)
        XCTAssertEqual(harness.transport.sentCount, RpcSocket.pingsBeforeTimeout)
    }

    func testPongInTimeKeepsTheSocketOpen() async {
        await assertTheSocketStaysOpen(after: pong)
    }

    func testAnyServerMessageCountsAsTheReply() async {
        await assertTheSocketStaysOpen(after: #"{"_tag":"Exit","requestId":"404","exit":{"_tag":"Success"}}"#)
    }

    func testLatePongAfterTheCloseDoesNothing() async {
        let harness = Harness()
        for _ in 0..<RpcSocket.pingsBeforeTimeout { _ = await harness.tick() }
        let event = await harness.tick()
        guard event == closed else { return XCTFail("the socket should close past the pong timeout, got \(event)") }
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

    private func assertTheSocketStaysOpen(after reply: String,
                                          file: StaticString = #filePath, line: UInt = #line) async {
        let harness = Harness()
        let firstPing = await harness.tick()
        XCTAssertEqual(firstPing, ping, file: file, line: line)
        harness.transport.deliver(reply)

        for _ in 0..<RpcSocket.pingsBeforeTimeout {
            let event = await harness.tick()
            XCTAssertEqual(event, ping, file: file, line: line)
            guard event == ping else { return }
        }

        let rest = await harness.untilAsleep()
        XCTAssertEqual(rest, .asleep(for: RpcSocket.pingInterval), file: file, line: line)
        XCTAssertFalse(harness.socket.isClosed, file: file, line: line)
        XCTAssertEqual(harness.closeCount, 0, file: file, line: line)
    }

    func testASocketClosedByTheClientIsFreedWhileItsCloseHandlerHoldsIt() {
        weak var freed: RpcSocket?
        do {
            let socket = RpcSocket(clock: TestClock())
            socket.open(FakeTransport()) { _ in withExtendedLifetime(socket) {} }
            freed = socket
            socket.close()
        }
        XCTAssertNil(freed)
    }

    func testASocketClosedByTheServerIsFreedWhileItsCloseHandlerHoldsIt() {
        weak var freed: RpcSocket?
        let transport = FakeTransport()
        do {
            let socket = RpcSocket(clock: TestClock())
            socket.open(transport) { _ in withExtendedLifetime(socket) {} }
            freed = socket
        }
        XCTAssertNotNil(freed)
        transport.dropConnection()
        XCTAssertNil(freed)
    }
}

private final class Harness: @unchecked Sendable {
    let pings: PingWatch
    let transport: FakeTransport
    let socket: RpcSocket
    private let lock = NSLock()
    private var closed = 0

    init() {
        let pings = PingWatch()
        self.pings = pings
        transport = FakeTransport { pings.record(.sent($0)) }
        socket = RpcSocket(clock: pings.recordingClock)
        socket.open(transport) { [weak self] failure in
            self?.countClose()
            pings.record(.closed(failure))
        }
        pings.watch(socket.pingLoop)
    }

    deinit {
        socket.close()
    }

    var clock: TestClock { pings.clock }
    var closeCount: Int { lock.withLock { closed } }

    private func countClose() {
        lock.withLock { closed += 1 }
    }

    func tick() async -> PingEvent? {
        await pings.tick()
    }

    func untilAsleep() async -> PingEvent? {
        await pings.untilAsleep()
    }
}

private final class FakeTransport: RpcTransport, @unchecked Sendable {
    typealias Receiver = @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void

    private let onSend: @Sendable (String) -> Void
    private let lock = NSLock()
    private var receiver: Receiver?
    private var sends = 0
    private var receives = 0
    private var closed = false

    init(onSend: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onSend = onSend
    }

    var sentCount: Int { lock.withLock { sends } }
    var receiveCount: Int { lock.withLock { receives } }
    var isClosed: Bool { lock.withLock { closed } }

    func resume() {}

    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { sends += 1 }
        onSend(text)
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
        takeReceiver()?(.success(.string(text)))
    }

    func dropConnection() {
        takeReceiver()?(.failure(URLError(.networkConnectionLost)))
    }

    private func takeReceiver() -> Receiver? {
        lock.withLock {
            defer { self.receiver = nil }
            return self.receiver
        }
    }
}
