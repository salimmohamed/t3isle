import XCTest
@testable import T3IsleCore

enum LinkedFixtures {
    static func structured<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try WireDecoder.make().decode(type, from: McpReply.structuredContent(Fixture.data(name)))
    }

    static func threads(in environment: LinkedEnvironment) throws -> [ThreadShell] {
        try structured("linked-threads.json", as: LinkedThreadPage.self).threads.map { $0.shell(in: environment) }
    }

    static func projects() throws -> [ProjectShell] {
        try structured("linked-projects.json", as: LinkedProjectPage.self).projects
    }

    static func chunkValues(_ name: String) throws -> [Any] {
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixture.data(name)) as? [String: Any])
        return try XCTUnwrap(message["values"] as? [Any])
    }
}

final class LinkedThreadsTests: XCTestCase {
    private let wsl = LinkedEnvironment(id: "env-wsl", label: "WSL")

    func testOnlyReachableLinksAreRead() throws {
        let list = try LinkedFixtures.structured("linked-environments.json", as: LinkedEnvironmentList.self)
        XCTAssertEqual(list.reachable, [LinkedEnvironment(id: "env-macbook", label: "MacBook Pro"), wsl])
    }

    func testListedThreadsCarryTheirEnvironment() throws {
        let shells = try LinkedFixtures.threads(in: wsl)
        XCTAssertEqual(shells.map(\.id), ["wsl-replied", "wsl-question", "thread:delegated-task:review", "wsl-watching"])
        XCTAssertTrue(shells.allSatisfy { $0.linkedEnvironment == wsl })
        let thread = InboxBuilder().thread(from: shells[0], project: nil, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(thread.environment, wsl)
        XCTAssertEqual(thread.model, "claude-opus-5-5")
    }

    func testRemoteMoodsFollowTheListedStatus() throws {
        let shells = try LinkedFixtures.threads(in: wsl)
        XCTAssertEqual(shells.map(InboxBuilder.mood), [.replied, .needsYou, .working, .waiting])
        XCTAssertTrue(InboxBuilder.hasPendingRequest(shells[1]))
        XCTAssertFalse(InboxBuilder.hasPendingRequest(shells[3]))
    }

    func testAQuestionNextToADevServerStillNeedsYou() throws {
        let page = try JSONSerialization.jsonObject(with: McpReply.structuredContent(Fixture.data("linked-threads.json")))
        let items = try XCTUnwrap((page as? [String: Any])?["threads"] as? [[String: Any]])
        var asking = try XCTUnwrap(items.first { $0["threadId"] as? String == "wsl-question" })
        asking["pendingBackgroundTasks"] = [["taskId": "dev", "kind": "command"]]
        let item = try WireDecoder.make().decode(LinkedThreadItem.self, from: JSONSerialization.data(withJSONObject: asking))
        XCTAssertEqual(InboxBuilder.mood(item.shell(in: wsl)), .needsYou)
    }

    func testAnUnreachableEnvironmentFailsQuietlyWithItsReason() throws {
        XCTAssertThrowsError(try McpReply.structuredContent(Fixture.data("linked-unreachable.json"))) { error in
            XCTAssertEqual(error as? T3Failure, .rejected("Main PC did not answer at https://main-pc.example.ts.net:3773."))
        }
    }

    func testAnAccessRefusalReadsShort() throws {
        XCTAssertThrowsError(try McpReply.structuredContent(Fixture.data("linked-escalation.json"))) { error in
            XCTAssertEqual(error as? T3Failure,
                           .rejected("This thread runs with more access than a linked machine allows. Open it in T3 Code."))
        }
    }

    func testRelayedSnapshotDecodesAsAThreadProjection() throws {
        let projection = try T3ServerClient.relaySnapshot(LinkedFixtures.chunkValues("linked-detail.json"))
        XCTAssertEqual(projection.thread.id, "wsl-question")
        XCTAssertFalse(DetailBuilder.prompts(projection, title: "Pick a retry policy", project: "deploy-tools").isEmpty)
    }

    func testCommandsBecomeToolCallsInTheThreadsEnvironment() throws {
        let answer = try LinkedCommand.tool(for: .answer(threadId: "wsl-question", requestId: "req-q",
                                                         answers: ["retries": .text("5")]), in: "env-wsl")
        XCTAssertEqual(answer.name, "t3_pending_request")
        XCTAssertEqual(answer.arguments["environmentId"] as? String, "env-wsl")
        XCTAssertEqual(answer.arguments["action"] as? String, "respond")
        XCTAssertEqual((answer.arguments["answers"] as? [String: Any])?["retries"] as? String, "5")

        let settle = try LinkedCommand.tool(for: .settle(threadId: "wsl-replied"), in: "env-wsl")
        XCTAssertEqual(settle.name, "t3_thread_organize")
        XCTAssertEqual(settle.arguments["action"] as? String, "settle")

        let stop = try LinkedCommand.tool(for: .stop(threadId: "wsl-question"), in: "env-wsl")
        XCTAssertEqual(stop.name, "t3_thread_interrupt")
        XCTAssertEqual(stop.arguments["stop"] as? Bool, true)

        XCTAssertThrowsError(try LinkedCommand.tool(for: .approve(threadId: "wsl-question", requestId: "req-cmd",
                                                                  decision: .accept), in: "env-wsl"))
    }
}
