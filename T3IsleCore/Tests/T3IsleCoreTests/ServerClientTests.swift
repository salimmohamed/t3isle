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
