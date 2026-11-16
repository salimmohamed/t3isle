import Combine
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

    func testClosedPresenceClearsWhenDisabled() async throws {
        let model = try await startedModel()
        var observed: [ClosedPresence] = []
        let observer = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { observed.append(model.closedPresence) }
        model.apply(T3Preferences(enabled: false))
        try await until { observed.contains(.none) }
        XCTAssertEqual(model.closedPresence, .none)
        observer.cancel()
        model.apply(T3Preferences(enabled: true))
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

private final class FixtureSource: T3Source, @unchecked Sendable {
    private let snapshot: ShellSnapshot
    private var continuation: AsyncStream<ShellUpdate>.Continuation?

    init(_ snapshot: ShellSnapshot) {
        self.snapshot = snapshot
    }

    func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        self.continuation = continuation
        continuation.yield(.snapshot(snapshot))
        return stream
    }

    func detail(threadId: String) async throws -> ThreadProjection {
        throw CancellationError()
    }

    func send(_ command: T3Command) async throws {}
    func environmentId() async -> String? { nil }
    func providers() -> [ProviderLimits] { [] }
    func signOut() async {}
}

@MainActor
final class SubagentVisibilityTests: XCTestCase {
    private func model() async throws -> T3IsleModel {
        let snapshot = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let model = T3IsleModel(source: FixtureSource(snapshot), opener: { _ in })
        model.start()
        let deadline = Date().addingTimeInterval(5)
        while model.threads.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        return model
    }

    private func shownIds(_ model: T3IsleModel) -> Set<String> {
        Set(model.threads.map(\.id) + model.allCards.map(\.id))
    }

    func testSubagentThreadsHiddenByDefault() async throws {
        let model = try await model()
        let ids = shownIds(model)
        XCTAssertTrue(ids.contains("t-working"))
        XCTAssertFalse(ids.contains("t-subagent"))
        XCTAssertFalse(ids.contains("t-delegated"))
        XCTAssertEqual(model.workingCount, 2)
        model.stop()
    }

    func testSideChatsHiddenByDefault() async throws {
        let model = try await model()
        XCTAssertFalse(shownIds(model).contains("t-side-chat"))
        XCTAssertEqual(model.workingCount, 2)
        model.stop()
    }

    func testShowSubagentsSettingKeepsSideChatsHidden() async throws {
        let model = try await model()
        model.apply(T3Preferences(showSubagents: true))
        let ids = shownIds(model)
        XCTAssertTrue(ids.contains("t-subagent"))
        XCTAssertFalse(ids.contains("t-side-chat"))
        XCTAssertEqual(model.workingCount, 4)
        model.stop()
    }

    func testSettingShowsSubagentThreads() async throws {
        let model = try await model()
        model.apply(T3Preferences(showSubagents: true))
        let ids = shownIds(model)
        XCTAssertTrue(ids.isSuperset(of: ["t-working", "t-subagent", "t-delegated"]))
        XCTAssertEqual(model.workingCount, 4)
        model.apply(T3Preferences())
        XCTAssertFalse(shownIds(model).contains("t-subagent"))
        model.stop()
    }
}
