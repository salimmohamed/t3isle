import XCTest
@testable import T3IsleCore

final class ScenarioTests: XCTestCase {
    func testShipsTheDocumentedScenarios() {
        XCTAssertEqual(Scenario.names, ["busy-session", "idle", "linked-rows", "plan-done", "question", "quota-low", "showcase"])
    }

    func testEveryBundledScenarioDecodesEveryLine() throws {
        for name in Scenario.names {
            do {
                let scenario = try Scenario.named(name)
                XCTAssertFalse(scenario.summary.isEmpty, name)
                XCTAssertGreaterThan(try scenario.events(startingAt: Scenario.anchor).count, 0, name)
            } catch {
                XCTFail("\(name): \(error.localizedDescription)")
            }
        }
    }

    func testUnknownScenarioListsTheKnownOnes() {
        XCTAssertThrowsError(try Scenario.named("nope")) {
            XCTAssertEqual($0 as? ScenarioError, .unknown("nope", known: Scenario.names))
        }
    }

    func testMalformedLineReportsItsLineNumber() {
        let cases: [(String, Int)] = [
            ("{\"scenario\":\"other\",\"summary\":\"s\"}", 1),
            ("{\"scenario\":\"bad\",\"summary\":\"s\"}\n{\"afterMs\":5}", 2),
            ("{\"scenario\":\"bad\",\"summary\":\"s\"}\n\n{\"shell\":{\"kind\":\"thread.updated\",\"thread\":{\"id\":\"t\"}}}", 3),
            ("{\"scenario\":\"bad\",\"summary\":\"s\"}\n{\"afterMs\":-1,\"detail\":{}}", 2),
            ("{\"scenario\":\"bad\",\"summary\":\"s\"}\n{\"provider\":{\"id\":\"codex\",\"file\":{\"enabled\":true}}}", 2),
        ]
        for (text, line) in cases {
            XCTAssertThrowsError(try Scenario.parse(Data(text.utf8), name: "bad"), text) { error in
                guard case .malformed("bad", let reported, _)? = error as? ScenarioError else {
                    return XCTFail("\(error)")
                }
                XCTAssertEqual(reported, line, text)
            }
        }
    }

    func testRecordedDatesMoveWithTheReplayStart() throws {
        let text = """
        {"scenario":"shift","summary":"s"}
        {"afterMs":250,"shell":{"kind":"thread.updated","thread":{"id":"t","title":"T","status":"running","updatedAt":"2026-01-01T00:00:10.000Z"}}}
        """
        let scenario = try Scenario.parse(Data(text.utf8), name: "shift")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let events = try scenario.events(startingAt: start)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.after, .milliseconds(250))
        guard case .shell(.threadUpdated(let shell, archived: false))? = events.first?.event else {
            return XCTFail("expected a thread update")
        }
        XCTAssertEqual(shell.updatedAt, start.addingTimeInterval(10))
    }
}

final class ReplaySourceTests: XCTestCase {
    func testStepsWaitForTheClockAndRecordedDatesStartAtItsNow() async throws {
        let clock = TestClock()
        let source = ReplaySource(scenario: nil, clock: clock)
        let progress = source.progress()
        source.play(try Scenario.named("plan-done"))
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 1.5])
        let running = try XCTUnwrap(source.threads.first)
        XCTAssertEqual(running.status, "running")
        XCTAssertEqual(running.updatedAt, clock.now)

        clock.advance(by: 1.5)
        _ = await progress.first { $0 == .finished("plan-done") }
        let completed = try XCTUnwrap(source.threads.first)
        XCTAssertEqual(completed.status, "completed")
        XCTAssertEqual(completed.latestRunCompletedAt, clock.now)
    }
}

private struct NotAThreadUpdate: Error {}

final class ReplayWorldTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func showcase() throws -> ReplayWorld {
        var world = ReplayWorld()
        for (_, event) in try Scenario.named("showcase").events(startingAt: now) {
            _ = world.apply(event)
        }
        return world
    }

    private func shell(_ update: ShellUpdate) throws -> ThreadShell {
        guard case .threadUpdated(let shell, archived: false) = update else { throw NotAThreadUpdate() }
        return shell
    }

    func testApproveThenAnswerClearsEachRequestAndRecomputesPending() throws {
        var world = try showcase()
        let approved = try shell(world.respond(to: .approve(threadId: "demo-webhooks", requestId: "demo-webhooks-approval-1",
                                                            decision: .accept), at: now))
        XCTAssertEqual(approved.pendingRuntimeRequest?.id, "demo-webhooks-question-1")
        XCTAssertEqual(approved.activityRunStatus, "waiting")
        XCTAssertEqual(world.projections["demo-webhooks"]?.runtimeRequests.map(\.id), ["demo-webhooks-question-1"])
        XCTAssertFalse(world.projections["demo-webhooks"]?.turnItems.contains { $0.requestId == "demo-webhooks-approval-1" } ?? true)

        let answered = try shell(world.respond(to: .answer(threadId: "demo-webhooks", requestId: "demo-webhooks-question-1",
                                                           answers: ["retries": .choices(["5xx"])]), at: now))
        XCTAssertNil(answered.pendingRuntimeRequest)
        XCTAssertEqual(answered.activityRunStatus, "running")
        XCTAssertEqual(InboxBuilder.mood(answered), .working)
        XCTAssertEqual(world.projections["demo-webhooks"]?.runtimeRequests, [])
        XCTAssertEqual(world.snapshot.threads.first { $0.id == "demo-webhooks" }, answered)
    }

    func testStopInterruptsTheThread() throws {
        var world = try showcase()
        let stopped = try shell(world.respond(to: .stop(threadId: "demo-checkout"), at: now))
        XCTAssertEqual(stopped.status, "interrupted")
        XCTAssertNil(stopped.activityRunStatus)
        XCTAssertNil(stopped.pendingRuntimeRequest)
        XCTAssertEqual(stopped.latestRunCompletedAt, now)
        XCTAssertEqual(world.projections["demo-checkout"]?.runs.last?.status, "interrupted")
    }

    func testSnoozeAndSettleSetTheirFields() throws {
        var world = try showcase()
        let until = now.addingTimeInterval(3600)
        XCTAssertEqual(try shell(world.respond(to: .snooze(threadId: "demo-roadmap", until: until), at: now)).snoozedUntil, until)
        XCTAssertNil(try shell(world.respond(to: .unsnooze(threadId: "demo-roadmap"), at: now)).snoozedUntil)
        XCTAssertEqual(try shell(world.respond(to: .settle(threadId: "demo-roadmap"), at: now)).settledOverride, "settled")
        XCTAssertNil(try shell(world.respond(to: .unsettle(threadId: "demo-roadmap"), at: now)).settledOverride)
    }

    func testUnknownThreadIsNotFound() throws {
        var world = try showcase()
        XCTAssertThrowsError(try world.respond(to: .stop(threadId: "missing"), at: now)) {
            XCTAssertEqual($0 as? T3Failure, .http(404, "Thread not found"))
        }
    }
}
