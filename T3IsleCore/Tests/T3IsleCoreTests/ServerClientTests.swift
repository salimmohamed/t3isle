import Network
import XCTest
@testable import T3IsleCore

final class ServerClientTests: XCTestCase {
    func testDisconnectDuringConnectClosesSocket() async throws {
        let server = try await SocketServer.start()
        let home = try Self.home(port: server.port)
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

    private static func home(port: UInt16) throws -> T3Home {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let userdata = root.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtime = #"{"origin":"http://127.0.0.1:\#(port)"}"#
        try Data(runtime.utf8).write(to: userdata.appendingPathComponent("server-runtime.json"))
        return T3Home(root: root)
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
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SocketServer")
    private let lock = NSLock()
    private var openCount = 0
    private var readiness: CheckedContinuation<Void, Error>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    static func start() async throws -> SocketServer {
        let server = try SocketServer()
        try await server.listen()
        return server
    }

    private init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    deinit {
        listener.cancel()
    }

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

    private func listen() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { readiness = continuation }
            listener.stateUpdateHandler = { [weak self] state in self?.changed(state) }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    private func changed(_ state: NWListener.State) {
        let result: Result<Void, Error>
        switch state {
        case .ready: result = .success(())
        case .failed(let error): result = .failure(error)
        default: return
        }
        let waiter: CheckedContinuation<Void, Error>? = lock.withLock {
            defer { readiness = nil }
            return readiness
        }
        waiter?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        openCount += 1
        lock.unlock()
        connection.start(queue: queue)
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
