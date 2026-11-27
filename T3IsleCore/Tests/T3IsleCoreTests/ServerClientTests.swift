import Network
import XCTest
@testable import T3IsleCore

final class ServerClientTests: XCTestCase {
    func testDisconnectDuringConnectClosesSocket() async throws {
        let server = try await SocketServer.start()
        let home = try T3Home.local(port: server.port)
        let runner = HeldRunner()
        let client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: runner))

        let updates = await client.shellUpdates()
        await runner.started()
        await client.disconnect()
        runner.release()

        var disconnected = false
        for await update in updates {
            if case .disconnected = update {
                disconnected = true
                break
            }
        }
        XCTAssertTrue(disconnected, "stream ended without reporting the disconnect")
        await server.idle()
    }

    func testTheClientClockTimesOutAnUnansweredSocket() async throws {
        let server = try await SocketServer.start()
        let home = try T3Home.local(port: server.port)
        let clock = TestClock()
        let client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: CountingRunner()),
                                    clock: clock)

        var updates = await client.shellUpdates().makeAsyncIterator()
        for _ in 0...RpcSocket.pingsBeforeTimeout {
            await clock.waitForSleepers()
            clock.advance(by: RpcSocket.pingInterval)
        }

        guard case .disconnected(.notRunning)? = await updates.next() else {
            return XCTFail("an unanswered socket should disconnect on the client's clock")
        }
        await server.idle()
    }
    func testADispatchInFlightWhenABadSnapshotClosesTheSocketIsSentAgainAfterTheReconnect() async throws {
        let server = try await RpcServer.start()
        let home = try T3Home.local(port: server.port)
        let client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: CountingRunner()),
                                    clock: TestClock())
        var events = server.events.makeAsyncIterator()

        let updates = await client.shellUpdates()
        guard case .request(let subscribe)? = await events.next() else { return XCTFail("the shell subscription never arrived") }
        XCTAssertEqual(subscribe.tag, "orchestration.subscribeShell")

        Task {
            do {
                server.record(.dispatched(try await client.dispatch(.settle(threadId: "thread-1"))))
            } catch {
                server.record(.failed(error as? T3Failure))
            }
        }
        guard case .request(let sent)? = await events.next() else { return XCTFail("the dispatch never arrived") }
        XCTAssertEqual(sent.tag, "orchestration.dispatchCommand")
        XCTAssertEqual(sent.connection, subscribe.connection)

        server.send(["_tag": "Chunk", "requestId": subscribe.id, "values": [["kind": "snapshot", "snapshot": [String: Any]()]]],
                    on: subscribe.connection)
        let afterTheClose = await events.next()
        guard case .request(let resent)? = afterTheClose else {
            return XCTFail("the dispatch should be sent again after the reconnect, got \(String(describing: afterTheClose))")
        }
        XCTAssertEqual(resent.tag, "orchestration.dispatchCommand")
        XCTAssertNotEqual(resent.connection, sent.connection)
        XCTAssertEqual(resent.commandId, sent.commandId)

        server.send(["_tag": "Exit", "requestId": resent.id, "exit": ["_tag": "Success", "value": ["sequence": 7]]],
                    on: resent.connection)
        let finished = await events.next()
        XCTAssertEqual(finished, .dispatched(7))

        var shell: [String] = []
        for await update in updates { shell.append(String(describing: update)) }
        XCTAssertEqual(shell.last, String(describing: ShellUpdate.disconnected(.unreadable)))
        await client.disconnect()
    }
}

private final class HeldRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private let (starts, starting) = AsyncStream<Void>.makeStream()

    func started() async {
        var iterator = starts.makeAsyncIterator()
        await iterator.next()
    }

    func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            waiter = continuation
            lock.unlock()
            starting.yield()
        }
        return Data(#"{"token":"held","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8)
    }

    func release() {
        lock.lock()
        let waiter = waiter
        lock.unlock()
        waiter?.resume()
    }
}

private final class SocketServer: @unchecked Sendable {
    private let listener: LocalListener
    private let lock = NSLock()
    private var openCount = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    static func start() async throws -> SocketServer {
        let server = try SocketServer()
        try await server.listener.start { [weak server] connection in server?.accept(connection) }
        return server
    }

    private init() throws {
        listener = try LocalListener(label: "SocketServer")
    }

    var port: UInt16 { listener.port }

    func idle() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isIdle: Bool = lock.withLock {
                guard openCount > 0 else { return true }
                idleWaiters.append(continuation)
                return false
            }
            if isIdle { continuation.resume() }
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        openCount += 1
        lock.unlock()
        drain(connection)
    }

    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                let idle: [CheckedContinuation<Void, Never>] = self.lock.withLock {
                    self.openCount -= 1
                    guard self.openCount == 0 else { return [] }
                    defer { self.idleWaiters.removeAll() }
                    return self.idleWaiters
                }
                connection.cancel()
                for waiter in idle { waiter.resume() }
            } else {
                self.drain(connection)
            }
        }
    }
}

private final class RpcServer: @unchecked Sendable {
    struct Request: Equatable {
        let connection: Int
        let id: String
        let tag: String
        let commandId: String?
    }

    enum Event: Equatable {
        case request(Request)
        case dispatched(Int?)
        case failed(T3Failure?)
    }

    private let listener: LocalListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private let recorder: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    static func start() async throws -> RpcServer {
        let server = try RpcServer()
        try await server.listener.start { [weak server] connection in server?.accept(connection) }
        return server
    }

    private init() throws {
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
        listener = try LocalListener(label: "RpcServer", parameters: parameters)
        (events, recorder) = AsyncStream.makeStream(of: Event.self)
    }

    var port: UInt16 { listener.port }

    func record(_ event: Event) {
        recorder.yield(event)
    }

    func send(_ message: [String: Any], on connection: Int) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let context = NWConnection.ContentContext(identifier: "message", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        lock.withLock { connections[connection] }
            .send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func accept(_ connection: NWConnection) {
        let number: Int = lock.withLock {
            connections.append(connection)
            return connections.count - 1
        }
        receive(on: connection, number: number)
    }

    private func receive(on connection: NWConnection, number: Int) {
        connection.receiveMessage { [weak self] data, context, _, error in
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            guard let self, error == nil, metadata?.opcode != .close else { return }
            if let data, let request = Self.request(data, on: number) { self.record(.request(request)) }
            self.receive(on: connection, number: number)
        }
    }

    private static func request(_ data: Data, on connection: Int) -> Request? {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              message["_tag"] as? String == "Request", let id = message["id"] as? String, let tag = message["tag"] as? String
        else { return nil }
        let payload = message["payload"] as? [String: Any]
        return Request(connection: connection, id: id, tag: tag, commandId: payload?["commandId"] as? String)
    }
}
