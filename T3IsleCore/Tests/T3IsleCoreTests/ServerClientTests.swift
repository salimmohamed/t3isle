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
        let client = try Self.client(of: server)
        var events = server.events.makeAsyncIterator()
        var shell: [RpcServer.Event] = []
        guard let resent = await Self.resendAfterABadSnapshot(client, server: server, events: &events, shell: &shell)
        else { return }

        server.send(["_tag": "Exit", "requestId": resent.id, "exit": ["_tag": "Success", "value": ["sequence": 7]]],
                    on: resent.connection)
        let finished = await Self.next(&events, collectingShellInto: &shell)
        XCTAssertEqual(finished, .dispatched(7))

        while shell.last != .shellEnded, let event = await events.next() { shell.append(event) }
        XCTAssertEqual(shell.suffix(2), [.shell(String(describing: ShellUpdate.disconnected(.unreadable))), .shellEnded])
        await client.disconnect()
    }

    func testAResentDispatchFailsAsUnreadableWhenTheReconnectsSnapshotIsUnreadableToo() async throws {
        let server = try await RpcServer.start()
        let client = try Self.client(of: server)
        var events = server.events.makeAsyncIterator()
        var shell: [RpcServer.Event] = []
        guard let resent = await Self.resendAfterABadSnapshot(client, server: server, events: &events, shell: &shell)
        else { return }

        server.watch(await client.shellUpdates())
        let resubscribed = await Self.next(&events, collectingShellInto: &shell)
        guard case .request(let subscribe)? = resubscribed, subscribe.tag == "orchestration.subscribeShell" else {
            return XCTFail("the second shell subscription never arrived, got \(String(describing: resubscribed))")
        }
        XCTAssertEqual(subscribe.connection, resent.connection)

        Self.sendAnUnreadableSnapshot(for: subscribe, on: server)
        let afterTheSecondClose = await Self.next(&events, collectingShellInto: &shell)
        XCTAssertEqual(afterTheSecondClose, .failed(.unreadable))
        await client.disconnect()
    }

    func testADispatchInFlightDuringADisconnectFailsWithoutAResend() async throws {
        let server = try await RpcServer.start()
        let client = try Self.client(of: server)
        var events = server.events.makeAsyncIterator()

        server.dispatch(.settle(threadId: "thread-1"), through: client)
        let first = await events.next()
        guard case .request(let sent)? = first else {
            return XCTFail("the dispatch never arrived, got \(String(describing: first))")
        }
        XCTAssertEqual(sent.tag, "orchestration.dispatchCommand")

        await client.disconnect()
        let afterTheDisconnect = await events.next()
        XCTAssertEqual(afterTheDisconnect, .failed(.notRunning))
    }

    private static func client(of server: RpcServer) throws -> T3ServerClient {
        let home = try T3Home.local(port: server.port)
        return T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: CountingRunner()),
                              clock: TestClock())
    }

    private static func resendAfterABadSnapshot(_ client: T3ServerClient, server: RpcServer,
                                                events: inout AsyncStream<RpcServer.Event>.Iterator,
                                                shell: inout [RpcServer.Event],
                                                file: StaticString = #filePath, line: UInt = #line) async -> RpcServer.Request? {
        server.watch(await client.shellUpdates())
        let first = await events.next()
        guard case .request(let subscribe)? = first else {
            XCTFail("the shell subscription never arrived, got \(String(describing: first))", file: file, line: line)
            return nil
        }
        XCTAssertEqual(subscribe.tag, "orchestration.subscribeShell", file: file, line: line)

        server.dispatch(.settle(threadId: "thread-1"), through: client)
        let second = await events.next()
        guard case .request(let sent)? = second else {
            XCTFail("the dispatch never arrived, got \(String(describing: second))", file: file, line: line)
            return nil
        }
        XCTAssertEqual(sent.tag, "orchestration.dispatchCommand", file: file, line: line)
        XCTAssertEqual(sent.connection, subscribe.connection, file: file, line: line)

        sendAnUnreadableSnapshot(for: subscribe, on: server)
        let afterTheClose = await next(&events, collectingShellInto: &shell)
        guard case .request(let resent)? = afterTheClose else {
            XCTFail("the dispatch should be sent again after the reconnect, got \(String(describing: afterTheClose))",
                    file: file, line: line)
            return nil
        }
        XCTAssertEqual(resent.tag, "orchestration.dispatchCommand", file: file, line: line)
        XCTAssertNotEqual(resent.connection, sent.connection, file: file, line: line)
        XCTAssertEqual(resent.commandId, sent.commandId, file: file, line: line)
        return resent
    }

    private static func sendAnUnreadableSnapshot(for subscribe: RpcServer.Request, on server: RpcServer) {
        server.send(["_tag": "Chunk", "requestId": subscribe.id, "values": [["kind": "snapshot", "snapshot": [String: Any]()]]],
                    on: subscribe.connection)
    }

    private static func next(_ events: inout AsyncStream<RpcServer.Event>.Iterator,
                             collectingShellInto shell: inout [RpcServer.Event]) async -> RpcServer.Event? {
        while let event = await events.next() {
            switch event {
            case .shell, .shellEnded: shell.append(event)
            case .request, .dispatched, .failed: return event
            }
        }
        return nil
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
        case shell(String)
        case shellEnded
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

    private func record(_ event: Event) {
        recorder.yield(event)
    }

    func dispatch(_ command: T3Command, through client: T3ServerClient) {
        Task {
            do {
                record(.dispatched(try await client.dispatch(command)))
            } catch {
                record(.failed(error as? T3Failure))
            }
        }
    }

    func watch(_ updates: AsyncStream<ShellUpdate>) {
        Task {
            for await update in updates { record(.shell(String(describing: update))) }
            record(.shellEnded)
        }
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
