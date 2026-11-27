import Foundation
import Network
@testable import T3IsleCore

enum McpTestClient {
    static func make(server: McpTestServer, runner: CountingRunner, clock: any T3Clock) throws -> T3ServerClient {
        let home = try T3Home.local(port: server.port)
        let linkSignIn = T3SignIn(home: home, store: MemoryTokenStore(), runner: runner, subject: "mcp-client",
                                  clock: TestClock())
        return T3ServerClient(home: home, signIn: T3SignIn(home: home, store: MemoryTokenStore(), runner: runner),
                              linkSignIn: linkSignIn, clock: clock)
    }
}

final class WatchedClock: T3Clock, @unchecked Sendable {
    private let base = TestClock()
    let (reads, reading) = AsyncStream<Void>.makeStream()

    var now: Date {
        reading.yield()
        return base.now
    }

    func sleep(until deadline: Date) async throws {
        try await base.sleep(until: deadline)
    }
}

final class CountingRunner: CommandRunner, @unchecked Sendable {
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

final class McpTestServer: @unchecked Sendable {
    private static let rejection = response("401 Unauthorized")
    private static let acceptance = response("202 Accepted")
    private static let noLinks = response("200 OK", body: #"{"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"links":[]}}}"#)

    private static func response(_ status: String, session: String? = nil, body: String = "") -> Data {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
        if let session { head += "MCP-Session-Id: \(session)\r\n" }
        return Data((head + "Connection: close\r\n\r\n" + body).utf8)
    }

    private struct HeldReply {
        let connection: NWConnection
        let reply: Data
    }

    private let listener: LocalListener
    private let lock = NSLock()
    private var answered = 0
    private var initializeCount = 0
    private var rejectsAll = true
    private var holdsInitialize = false
    private var held: HeldReply?
    private var pairsRejections = false
    private var unpairedToolCall: NWConnection?
    let (initializeArrivals, initializeArrived) = AsyncStream<Void>.makeStream()

    static func start() async throws -> McpTestServer {
        let server = try McpTestServer()
        try await server.listener.start { [weak server] connection in server?.read(connection, buffered: Data()) }
        return server
    }

    private init() throws {
        listener = try LocalListener(label: "McpTestServer")
    }

    var port: UInt16 { listener.port }

    var requests: Int { lock.withLock { answered } }

    var initializes: Int { lock.withLock { initializeCount } }

    var rejecting: Bool {
        get { lock.withLock { rejectsAll } }
        set { lock.withLock { rejectsAll = newValue } }
    }

    var rejectsToolCallsInPairs: Bool {
        get { lock.withLock { pairsRejections } }
        set { lock.withLock { pairsRejections = newValue } }
    }

    func holdNextInitialize() {
        lock.withLock { holdsInitialize = true }
    }

    func releaseInitialize() {
        let reply: HeldReply? = lock.withLock {
            defer { held = nil }
            return held
        }
        if let reply { send(reply.reply, on: reply.connection) }
    }

    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            let received = buffered + (chunk ?? Data())
            if Self.isWholeRequest(received) {
                self.answer(received, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffered: received)
            }
        }
    }

    private func answer(_ request: Data, on connection: NWConnection) {
        let text = String(decoding: request, as: UTF8.self)
        let isInitialize = text.contains(#""initialize""#)
        let replies: [HeldReply] = lock.withLock {
            answered += 1
            if isInitialize { initializeCount += 1 }
            if pairsRejections, !isInitialize, text.contains("tools") { return pairRejection(of: connection) }
            let reply = HeldReply(connection: connection, reply: rejectsAll ? Self.rejection : reply(to: text))
            guard isInitialize, holdsInitialize else { return [reply] }
            holdsInitialize = false
            held = reply
            return []
        }
        if isInitialize { initializeArrived.yield() }
        for reply in replies { send(reply.reply, on: reply.connection) }
    }

    private func pairRejection(of connection: NWConnection) -> [HeldReply] {
        guard let unpaired = unpairedToolCall else {
            unpairedToolCall = connection
            return []
        }
        unpairedToolCall = nil
        return [unpaired, connection].map { HeldReply(connection: $0, reply: Self.rejection) }
    }

    private func send(_ reply: Data, on connection: NWConnection) {
        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func reply(to text: String) -> Data {
        if text.contains("notifications") { return Self.acceptance }
        guard !text.contains("tools") else { return Self.noLinks }
        return Self.response("200 OK", session: "mcp-session-\(initializeCount)",
                             body: #"{"jsonrpc":"2.0","id":0,"result":{}}"#)
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
