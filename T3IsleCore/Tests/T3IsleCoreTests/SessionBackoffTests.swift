import XCTest
@testable import T3IsleCore

final class SessionBackoffTests: XCTestCase {
    func testRunOfRejectionsBacksOff() {
        let clock = TestClock()
        var backoff = SessionBackoff()

        backoff.rejected(at: clock.now)
        XCTAssertTrue(backoff.allows(at: clock.now))

        for wait: TimeInterval in [60, 120, 240, 300, 300] {
            backoff.rejected(at: clock.now)
            clock.advance(by: wait - 1)
            XCTAssertFalse(backoff.allows(at: clock.now))
            clock.advance(by: 1)
            XCTAssertTrue(backoff.allows(at: clock.now))
        }
    }

    func testRejectionDuringTheWaitIsIgnored() {
        let clock = TestClock()
        var backoff = SessionBackoff()
        backoff.rejected(at: clock.now)
        backoff.rejected(at: clock.now)
        clock.advance(by: 30)

        backoff.rejected(at: clock.now)

        XCTAssertEqual(backoff.rejections, 2)
        XCTAssertEqual(backoff.retryAt, clock.now + 30)
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
        let server = try await McpTestServer.start()
        let clock = TestClock()
        let runner = CountingRunner()
        let client = try McpTestClient.make(server: server, runner: runner, clock: clock)

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
        XCTAssertEqual(server.requests, 3)
    }

    func testSuccessfulCallEndsTheBackoff() async throws {
        let server = try await McpTestServer.start()
        let clock = TestClock()
        let runner = CountingRunner()
        let client = try McpTestClient.make(server: server, runner: runner, clock: clock)
        _ = await client.linkedRead()
        _ = await client.linkedRead()
        clock.advance(by: 60)
        server.rejecting = false

        let read = await client.linkedRead()

        XCTAssertNotNil(read)
        XCTAssertEqual(runner.issued, 3)
        server.rejecting = true
        _ = await client.linkedRead()
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 5)
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 5)
    }

    func testLinkedCommandStillTriesWhileBackingOff() async throws {
        let server = try await McpTestServer.start()
        let clock = TestClock()
        let runner = CountingRunner()
        let client = try McpTestClient.make(server: server, runner: runner, clock: clock)
        _ = await client.linkedRead()
        _ = await client.linkedRead()

        do {
            try await client.dispatch(.settle(threadId: "thread"), in: "environment")
            XCTFail("a rejected session should fail the command")
        } catch {
            XCTAssertEqual(error as? T3Failure, .signedOut)
        }

        XCTAssertEqual(runner.issued, 3)
        _ = await client.linkedRead()
        XCTAssertEqual(runner.issued, 3)
    }
}
