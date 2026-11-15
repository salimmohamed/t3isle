import Network
import XCTest
@testable import T3IsleCore

final class ServerClientTests: XCTestCase {
    func testDisconnectDuringConnectClosesSocket() async throws {
        let server = try SocketServer()
        let home = try Self.home(port: server.port)
        let runner = HeldRunner()
        let client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: runner))

        let updates = await client.shellUpdates()
        await fulfillment(of: [runner.started], timeout: 5)
        await client.disconnect()
        runner.release()

        try await Self.until { server.accepted > 0 }
        try await Self.until { server.openConnections == 0 }
        XCTAssertEqual(server.openConnections, 0, "socket stayed open after disconnect")
        _ = updates
    }

    private static func home(port: UInt16) throws -> T3Home {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let userdata = root.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtime = #"{"origin":"http://127.0.0.1:\#(port)"}"#
        try Data(runtime.utf8).write(to: userdata.appendingPathComponent("server-runtime.json"))
        return T3Home(root: root)
    }

    private static func until(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

private final class HeldRunner: CommandRunner, @unchecked Sendable {
    let started = XCTestExpectation(description: "sign-in started")
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?

    func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            waiter = continuation
            lock.unlock()
            started.fulfill()
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
    private var acceptedCount = 0
    private var openCount = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw T3Failure.notRunning }
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    deinit {
        listener.cancel()
    }

    var accepted: Int {
        lock.lock()
        defer { lock.unlock() }
        return acceptedCount
    }

    var openConnections: Int {
        lock.lock()
        defer { lock.unlock() }
        return openCount
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        acceptedCount += 1
        openCount += 1
        lock.unlock()
        connection.start(queue: queue)
        drain(connection)
    }

    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.lock.lock()
                self.openCount -= 1
                self.lock.unlock()
                connection.cancel()
            } else {
                self.drain(connection)
            }
        }
    }
}
