import XCTest
@testable import T3IsleCore

final class McpSessionTests: XCTestCase {
    func testConcurrentCallsShareOneInitialize() async throws {
        let server = try await McpTestServer.start()
        server.rejecting = false
        let (reads, runner) = try await Self.readTwiceDuringOneInitialize(server)

        XCTAssertEqual(server.initializes, 1)
        XCTAssertNotNil(reads.0)
        XCTAssertNotNil(reads.1)
        XCTAssertEqual(runner.issued, 1)
    }

    func testConcurrentCallsShareOneRejectedInitialize() async throws {
        let server = try await McpTestServer.start()
        let (reads, runner) = try await Self.readTwiceDuringOneInitialize(server)
        XCTAssertNil(reads.0)
        XCTAssertNil(reads.1)
        XCTAssertEqual(server.initializes, 1)
        XCTAssertEqual(runner.issued, 1)
    }

    func testASharedRejectionStillRetriesOnTheNextPassThenBacksOff() async throws {
        let server = try await McpTestServer.start()
        let clock = WatchedClock()
        let runner = CountingRunner()
        let client = try McpTestClient.make(server: server, runner: runner, clock: clock)
        _ = try await Self.readTwice(client, server: server, clock: clock)
        XCTAssertEqual(server.requests, 1)

        _ = await client.linkedRead()
        XCTAssertEqual(server.requests, 2)

        _ = await client.linkedRead()
        XCTAssertEqual(server.requests, 2)
    }

    func testConcurrentCallsRejectedAgainCountOneRejection() async throws {
        let server = try await McpTestServer.start()
        server.rejecting = false
        server.rejectsToolCallsInPairs = true
        let client = try McpTestClient.make(server: server, runner: CountingRunner(), clock: TestClock())
        async let first = client.linkedRead()
        async let second = client.linkedRead()
        let reads = await (first, second)
        XCTAssertNil(reads.0)
        XCTAssertNil(reads.1)
        XCTAssertEqual(server.initializes, 2)

        server.rejectsToolCallsInPairs = false
        server.rejecting = true
        let requests = server.requests
        _ = await client.linkedRead()
        XCTAssertEqual(server.requests, requests + 1)

        _ = await client.linkedRead()
        XCTAssertEqual(server.requests, requests + 1)
    }

    func testTurningPairingOffAnswersTheHeldToolCall() async throws {
        let server = try await McpTestServer.start()
        server.rejecting = false
        server.rejectsToolCallsInPairs = true
        let client = try McpTestClient.make(server: server, runner: CountingRunner(), clock: TestClock())
        var arrivals = server.arrivals.makeAsyncIterator()
        async let read = client.linkedRead()
        while let method = await arrivals.next(), method != "tools/call" {}

        server.rejectsToolCallsInPairs = false
        server.dropHeldCalls()
        let answered = await read
        XCTAssertNotNil(answered, "the held tool call should get its rejection, then the retry should read the links")
        XCTAssertEqual(server.initializes, 2)
    }

    private static func readTwiceDuringOneInitialize(_ server: McpTestServer) async throws
        -> ((LinkedRead?, LinkedRead?), CountingRunner) {
        let clock = WatchedClock()
        let runner = CountingRunner()
        let client = try McpTestClient.make(server: server, runner: runner, clock: clock)
        return (try await readTwice(client, server: server, clock: clock), runner)
    }

    private static func readTwice(_ client: T3ServerClient, server: McpTestServer,
                                  clock: WatchedClock) async throws -> (LinkedRead?, LinkedRead?) {
        server.holdNextInitialize()
        var checks = clock.reads.makeAsyncIterator()
        var arrivals = server.arrivals.makeAsyncIterator()
        async let first = client.linkedRead()
        await checks.next()
        await arrivals.next()
        async let second = client.linkedRead()
        await checks.next()
        server.releaseInitialize()
        return await (first, second)
    }
}
