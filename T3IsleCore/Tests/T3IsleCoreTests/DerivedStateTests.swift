import XCTest
@testable import T3IsleCore

final class DerivedStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_770_400)

    private func shell() throws -> ShellSnapshot {
        try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
    }

    private func detail() throws -> ThreadProjection {
        try WireDecoder.make().decode(ThreadDetailEnvelope.self, from: Fixture.data("detail-question.json")).projection
    }

    private func inbox() throws -> [T3Thread] {
        let snapshot = try shell()
        let projects = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        return InboxBuilder(providerNames: ["claudeAgent": "Claude"]).threads(from: snapshot.threads, projects: projects, now: now)
    }

    func testInboxExcludesSettled() throws {
        let ids = try inbox().map(\.id)
        XCTAssertFalse(ids.contains("t-settled"))
        XCTAssertEqual(ids.count, 8)
    }

    func testSubagentsAreChildOrDelegatedThreads() throws {
        let subagents = try shell().threads.filter(\.isSubagent).map(\.id)
        XCTAssertEqual(subagents, ["t-subagent", "t-delegated"])
    }

    func testMoodsAndOrdering() throws {
        let threads = try inbox()
        let mood = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0.mood) })
        XCTAssertEqual(mood["t-question"], .needsYou)
        XCTAssertEqual(mood["t-working"], .working)
        XCTAssertEqual(mood["t-replied"], .replied)
        XCTAssertEqual(mood["t-failed"], .failed)
        XCTAssertEqual(mood["t-waiting-pr"], .waiting)
        XCTAssertEqual(mood["t-snoozed"], .idle)
        XCTAssertEqual(threads.first?.id, "t-question")
        XCTAssertEqual(threads.map(\.mood), threads.map(\.mood).sorted())
    }

    func testThreadFieldsAndLines() throws {
        let threads = Dictionary(uniqueKeysWithValues: try inbox().map { ($0.id, $0) })
        let question = try XCTUnwrap(threads["t-question"])
        XCTAssertEqual(question.project, "payments-api")
        XCTAssertEqual(question.provider, "Claude")
        XCTAssertEqual(question.pendingRequestId, "req-q")
        XCTAssertEqual(question.line, "Should retries run on every webhook?")
        XCTAssertEqual(threads["t-replied"]?.line, "Rewrote the welcome copy in Welcome.tsx.")
        XCTAssertEqual(threads["t-failed"]?.line, "error: no such module 'PostgresNIO'")
        XCTAssertEqual(threads["t-waiting-pr"]?.status, "Waiting on PR #42")
        XCTAssertEqual(threads["t-working"]?.provider, "Codex")
        XCTAssertNotNil(threads["t-snoozed"]?.snoozedUntil)
    }

    func testSnoozeWakesForNewQuestion() {
        let snoozedAt = WireDate.parse("2026-11-15T13:00:00.000Z")
        var shell = ThreadShell(id: "s", title: "S", status: "completed",
                                snoozedUntil: now.addingTimeInterval(3600), snoozedAt: snoozedAt)
        XCTAssertTrue(InboxBuilder.isSnoozed(shell, now: now))
        shell.pendingRuntimeRequest = PendingRequestSummary(id: "r", kind: "user_input", createdAt: now)
        XCTAssertFalse(InboxBuilder.isSnoozed(shell, now: now))
        shell.pendingRuntimeRequest = PendingRequestSummary(id: "r", kind: "command", createdAt: snoozedAt)
        XCTAssertFalse(InboxBuilder.isSnoozed(shell, now: now))
    }

    func testDetailHeaderPlanAndActivity() throws {
        let detail = DetailBuilder.detail(try detail())
        XCTAssertEqual(detail.model, "claude-opus-5-5")
        XCTAssertEqual(detail.branch, "billing")
        XCTAssertEqual(detail.providerId, "claudeAgent")
        XCTAssertEqual(detail.runStartedAt, WireDate.parse("2026-11-15T19:00:02.000Z"))
        XCTAssertTrue(detail.isRunning)
        XCTAssertEqual(detail.plan?.steps.count, 3)
        XCTAssertEqual(detail.plan?.completed, 1)
        XCTAssertEqual(detail.plan?.current?.id, "s2")
        XCTAssertFalse(detail.plan?.isComplete ?? true)
        XCTAssertEqual(detail.activity.map(\.text), ["$ swift test --filter Webhooks", "Edited Webhooks.swift", "$ swift build"])
        XCTAssertEqual(detail.activity.map(\.inProgress), [false, false, true])
        XCTAssertEqual(detail.latestLine, "$ swift build")
    }

    func testPromptsFlattenQuestionsAndSkipIgnoredKinds() throws {
        let prompts = DetailBuilder.prompts(try detail(), title: "Refactor", project: "api")
        XCTAssertEqual(prompts.map(\.id), ["req-cmd", "req-q#q1", "req-q#q2"])
        guard case .approval(let choices) = prompts[0].kind else { return XCTFail("approval expected") }
        XCTAssertEqual(choices.map(\.decision), ["accept", "acceptForSession", "decline"])
        XCTAssertEqual(prompts[0].detail, "rm -rf .build")
        XCTAssertEqual(prompts[0].title, "Run a command?")
        guard case .question(let question, let index, let count) = prompts[1].kind else { return XCTFail("question expected") }
        XCTAssertEqual(question.options.map(\.answerValue), ["Every webhook", "5xx"])
        XCTAssertEqual(index, 0)
        XCTAssertEqual(count, 2)
        guard case .question(let free, _, _) = prompts[2].kind else { return XCTFail("question expected") }
        XCTAssertTrue(free.allowsFreeText)
    }

    func testPlanProgressCompletion() {
        let plan = PlanProgress(planId: "p", steps: [PlanStep(id: "a", text: "A", status: "completed")])
        XCTAssertTrue(plan.isComplete)
        XCTAssertNil(plan.current)
        XCTAssertFalse(PlanProgress(planId: "p", steps: []).isComplete)
    }
}
