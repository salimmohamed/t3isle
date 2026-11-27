import Network
import XCTest
@testable import T3IsleCore

final class SessionBackoffTests: XCTestCase {
    func testRunOfRejectionsBacksOff() {
        let clock = TestClock()
        var backoff = SessionBackoff()

        backoff.rejected(at: clock.now)
        XCTAssertTrue(backoff.allows(at: clock.now))

        for wait: TimeInterval in [60, 120, 240, 480, 960, 1800, 1800] {
            backoff.rejected(at: clock.now)
            clock.advance(by: wait - 1)
            XCTAssertFalse(backoff.allows(at: clock.now))
            clock.advance(by: 1)
            XCTAssertTrue(backoff.allows(at: clock.now))
        }
    }

    func testSuccessResetsBackoff() {
        let clock = TestClock()
        var backoff = SessionBackoff()
        for _ in 0..<4 { backoff.rejected(at: clock.now) }
        XCTAssertFalse(backoff.allows(at: clock.now))

        backoff.accepted()

        XCTAssertTrue(backoff.allows(at: clock.now))
        backoff.rejected(at: clock.now)
        XCTAssertTrue(backoff.allows(at: clock.now))
        backoff.rejected(at: clock.now)
        XCTAssertEqual(backoff.retryAt, clock.now + 60)
    }

    func testNoSessionIsIssuedWhileBackingOff() async throws {
        let server = try await RejectingServer.start()
        let home = try Self.home(port: server.port)
        let clock = TestClock()
        let runner = CountingRunner()
        let linkSignIn = T3SignIn(home: home, store: MemoryTokenStore(), runner: runner, subject: "mcp-client", clock: clock)
        let client = T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: runner),
                                    linkSignIn: linkSignIn, clock: clock)

        _ = await client.linkedRead()
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 2)
        XCTAssertEqual(server.requests, 2)

        for _ in 0..<5 {
            clock.advance(by: 10)
            _ = await client.linkedRead()
        }
        XCTAssertEqual(runner.issued, 2)
        XCTAssertEqual(server.requests, 2)

        clock.advance(by: 10)
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 3)
        XCTAssertEqual(server.requests, 3)

        clock.advance(by: 60)
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 3)
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

private final class CountingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var issued: Int { lock.withLock { count } }

    func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
        let number = lock.withLock {
            count += 1
            return count
        }
        return Data(#"{"token":"session-\#(number)","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8)
    }
}

private final class RejectingServer: @unchecked Sendable {
    private static let reply = Data("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)

    private let listener: NWListener
    private let queue = DispatchQueue(label: "RejectingServer")
    private let lock = NSLock()
    private var answered = 0
    private var readiness: CheckedContinuation<Void, Error>?

    static func start() async throws -> RejectingServer {
        let server = try RejectingServer()
        try await server.listen()
        return server
    }

    private init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    deinit {
        listener.cancel()
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    var requests: Int { lock.withLock { answered } }

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
        connection.start(queue: queue)
        read(connection, buffered: Data())
    }

    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            let received = buffered + (chunk ?? Data())
            if Self.isWholeRequest(received) {
                self.lock.withLock { self.answered += 1 }
                connection.send(content: Self.reply, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffered: received)
            }
        }
    }

    private static func isWholeRequest(_ data: Data) -> Bool {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).lowercased()
        let length = head.split(separator: "\r\n")
            .first { $0.hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        return data.count - end.upperBound >= length
    }
}
