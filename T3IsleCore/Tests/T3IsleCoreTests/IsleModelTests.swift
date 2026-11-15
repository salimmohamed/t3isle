import XCTest
@testable import T3IsleCore

@MainActor
final class IsleModelTests: XCTestCase {
    private func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func startedModel() async throws -> T3IsleModel {
        let model = T3IsleModel(source: DemoSource(), isDemo: true, opener: { _ in })
        model.start()
        try await until { model.prompts.count >= 4 }
        return model
    }

    func testDemoProducesInboxPromptsAndAgents() async throws {
        let model = try await startedModel()
        XCTAssertEqual(model.threads.first?.mood, .needsYou)
        XCTAssertTrue(model.threads.contains { $0.isSnoozed })
        XCTAssertEqual(Set(model.agentGroups.map(\.title)), ["web", "payments-api", "infra"])
        XCTAssertEqual(model.providers.count, 2)
        model.stop()
    }

    func testApprovalIsRemovedOptimistically() async throws {
        let model = try await startedModel()
        let approval = try XCTUnwrap(model.prompts.first { $0.isApproval })
        let before = model.prompts.count
        model.respond(approval, decision: .accept)
        XCTAssertEqual(model.prompts.count, before - 1)
        XCTAssertFalse(model.prompts.contains { $0.id == approval.id })
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertFalse(model.prompts.contains { $0.id == approval.id })
        model.stop()
    }

    func testMultiQuestionRequestSubmitsAfterLastAnswer() async throws {
        let model = try await startedModel()
        let questions = model.prompts.filter { !$0.isApproval }
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions.map(\.title), ["Retries", "Backoff"])
        model.answer(questions[0], with: .choices(["5xx"]))
        XCTAssertEqual(model.prompts.filter { !$0.isApproval }.map(\.id), [questions[1].id])
        model.answer(questions[1], with: .text("2 minutes"))
        XCTAssertTrue(model.prompts.filter { !$0.isApproval }.isEmpty)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(model.prompts.filter { !$0.isApproval }.isEmpty)
        model.stop()
    }

    func testSettleHidesThreadAndUndoRestoresIt() async throws {
        let model = try await startedModel()
        let thread = try XCTUnwrap(model.threads.first { $0.mood == .replied || $0.mood == .failed })
        model.settle(thread)
        XCTAssertFalse(model.threads.contains { $0.id == thread.id })
        XCTAssertNotNil(model.notice?.undo)
        model.undo()
        XCTAssertTrue(model.threads.contains { $0.id == thread.id })
        model.stop()
    }

    func testClosedPresenceIsActiveWhileQuestionsWait() async throws {
        let model = try await startedModel()
        XCTAssertEqual(model.closedPresence, .active)
        model.stop()
    }

    func testInterruptMarksCardStopping() async throws {
        let model = try await startedModel()
        let card = try XCTUnwrap(model.allCards.first { $0.state == .working })
        model.interrupt(card.id)
        XCTAssertEqual(model.allCards.first { $0.id == card.id }?.state, .stopping)
        model.stop()
    }
}
