import XCTest
@testable import T3IsleCore

final class WireProtocolTests: XCTestCase {
    private func json(_ command: T3Command) throws -> [String: Any] {
        try T3ServerClient.jsonObject(command.payload(commandId: "c1"))
    }

    func testApprovalCommand() throws {
        let body = try json(.approve(threadId: "t", requestId: "r", decision: .acceptForSession))
        XCTAssertEqual(body["type"] as? String, "runtime-request.respond")
        XCTAssertEqual(body["decision"] as? String, "acceptForSession")
        XCTAssertEqual(body["requestId"] as? String, "r")
        XCTAssertEqual(body["commandId"] as? String, "c1")
        XCTAssertNil(body["answers"])
    }

    func testAnswerCommand() throws {
        let body = try json(.answer(threadId: "t", requestId: "r", answers: ["q1": .choices(["5xx"]), "q2": .text("30s")]))
        let answers = try XCTUnwrap(body["answers"] as? [String: Any])
        XCTAssertEqual(answers["q1"] as? [String], ["5xx"])
        XCTAssertEqual(answers["q2"] as? String, "30s")
    }

    func testOrganizeAndStopCommands() throws {
        let until = try XCTUnwrap(WireDate.parse("2026-11-16T09:00:00.000Z"))
        XCTAssertEqual(try json(.snooze(threadId: "t", until: until))["snoozedUntil"] as? String, "2026-11-16T09:00:00.000Z")
        XCTAssertEqual(try json(.unsnooze(threadId: "t"))["reason"] as? String, "user")
        XCTAssertEqual(try json(.settle(threadId: "t"))["type"] as? String, "thread.settle")
        XCTAssertEqual(try json(.unsettle(threadId: "t"))["type"] as? String, "thread.unsettle")
        XCTAssertEqual(try json(.stop(threadId: "t"))["type"] as? String, "thread.stop")
    }

    func testRpcExitDecoding() {
        let success = RpcSocket.exitResult(["_tag": "Success", "value": ["sequence": 9]])
        XCTAssertEqual((try? success.get() as? [String: Int])?["sequence"], 9)
        let failure = RpcSocket.exitResult(["_tag": "Failure", "cause": [["_tag": "Fail", "error": ["_tag": "X", "message": "Request is not pending"]]]])
        XCTAssertEqual(failure.mapError { $0 }.failureValue, .rejected("Request is not pending"))
        XCTAssertEqual(RpcSocket.identifier(NSNumber(value: 3)), "3")
        XCTAssertEqual(RpcSocket.identifier("4"), "4")
    }

    func testShellStreamItems() throws {
        let threadUpdate: [String: Any] = ["kind": "thread.updated", "sequence": 3, "location": "active",
                                           "thread": ["id": "t", "title": "T", "status": "running"]]
        guard case .threadUpdated(let shell, let archived)? = T3ServerClient.shellUpdate(threadUpdate) else {
            return XCTFail("thread.updated expected")
        }
        XCTAssertEqual(shell.status, "running")
        XCTAssertFalse(archived)
        guard case .threadRemoved(let id)? = T3ServerClient.shellUpdate(["kind": "thread.removed", "threadId": "x", "sequence": 1]) else {
            return XCTFail("thread.removed expected")
        }
        XCTAssertEqual(id, "x")
        let snapshot = try JSONSerialization.jsonObject(with: Fixture.data("shell.json"))
        guard case .snapshot(let decoded)? = T3ServerClient.shellUpdate(["kind": "snapshot", "snapshot": snapshot]) else {
            return XCTFail("snapshot expected")
        }
        XCTAssertEqual(decoded.threads.count, 10)
    }

    func testEnrichmentSnapshotOnlyUpdatesProjects() {
        let enrichment: [String: Any] = [
            "kind": "snapshot",
            "resolvedRepositoryIdentityRoots": ["/Users/dev/web"],
            "snapshot": ["snapshotSequence": 9, "threads": [] as [Any], "archivedThreads": [] as [Any],
                         "projects": [["id": "p-web", "title": "web", "workspaceRoot": "/Users/dev/web"]]],
        ]
        let updates = T3ServerClient.shellUpdates(enrichment)
        XCTAssertEqual(updates.count, 1)
        guard case .projectUpdated(let project) = updates[0] else { return XCTFail("project update expected") }
        XCTAssertEqual(project.id, "p-web")
        let authoritative: [String: Any] = ["kind": "snapshot", "snapshot": ["threads": [] as [Any], "projects": [] as [Any], "snapshotSequence": 1]]
        guard case .snapshot? = T3ServerClient.shellUpdates(authoritative).first else { return XCTFail("snapshot expected") }
    }

    func testRequestOnClosedSocketFailsImmediately() {
        let socket = RpcSocket()
        socket.close()
        var outcome: T3Failure?
        socket.request("orchestration.subscribeShell", payload: [:]) { event in
            if case .exit(.failure(let failure)) = event { outcome = failure }
        }
        XCTAssertTrue(socket.isClosed)
        XCTAssertEqual(outcome, .notRunning)
    }

    func testIssuedSessionParsing() throws {
        let data = Data(#"{"sessionId":"s1","token":"abc","expiresAt":"2026-12-15T20:03:06.708Z"}"#.utf8)
        let token = try T3SignIn.parseIssued(data)
        XCTAssertEqual(token.token, "abc")
        XCTAssertEqual(token.sessionId, "s1")
        XCTAssertThrowsError(try T3SignIn.parseIssued(Data("{}".utf8)))
    }

    func testThreadIdsArePercentEncoded() {
        XCTAssertEqual(T3ServerClient.pathComponent("thread:a%3Ab"), "thread%3Aa%253Ab")
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
