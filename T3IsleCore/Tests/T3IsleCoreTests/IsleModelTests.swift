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
    private let projections: [String: ThreadProjection]
    private var continuation: AsyncStream<ShellUpdate>.Continuation?

    init(_ snapshot: ShellSnapshot, projections: [String: ThreadProjection] = [:]) {
        self.snapshot = snapshot
        self.projections = projections
    }

    func push(_ update: ShellUpdate) {
        continuation?.yield(update)
    }

    func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        self.continuation = continuation
        continuation.yield(.snapshot(snapshot))
        return stream
    }

    func detail(threadId: String) async throws -> ThreadProjection {
        guard let projection = projections[threadId] else { throw CancellationError() }
        return projection
    }

    func send(_ command: T3Command) async throws {}
    func environmentId() async -> String? { "env-local" }
    func providers() -> [ProviderLimits] { [] }
    func signOut() async {}
}

@MainActor
final class SubagentVisibilityTests: XCTestCase {
    private var snapshot: ShellSnapshot!
    private var source: FixtureSource!
    private var opened: [URL] = []

    override func setUp() async throws {
        snapshot = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let question = try WireDecoder.make()
            .decode(ThreadDetailEnvelope.self, from: Fixture.data("detail-question.json")).projection
        let projections = Dictionary(uniqueKeysWithValues: ["t-subagent", "t-side-chat"].map { id in
            var projection = question
            projection.thread.id = id
            for index in projection.runtimeRequests.indices {
                projection.runtimeRequests[index].id = "\(id)-\(projection.runtimeRequests[index].id)"
            }
            for index in projection.turnItems.indices {
                projection.turnItems[index].requestId = projection.turnItems[index].requestId.map { "\(id)-\($0)" }
            }
            return (id, projection)
        })
        source = FixtureSource(snapshot, projections: projections)
    }

    private func model() async throws -> T3IsleModel {
        let model = T3IsleModel(source: source, opener: { [weak self] url in self?.opened.append(url) })
        model.start()
        try await until { !model.threads.isEmpty }
        return model
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func shell(_ id: String) throws -> ThreadShell {
        try XCTUnwrap(snapshot.threads.first { $0.id == id })
    }

    private func ask(_ id: String) throws {
        var asking = try shell(id)
        asking.activityRunStatus = "waiting"
        asking.pendingRuntimeRequest = PendingRequestSummary(id: "\(id)-req-q", kind: "user_input")
        source.push(.threadUpdated(asking, archived: false))
    }

    private func resolve(_ id: String) throws {
        source.push(.threadUpdated(try shell(id), archived: false))
    }

    private func assertWaitingOnYouOnly(_ model: T3IsleModel, _ id: String) throws {
        let thread = try XCTUnwrap(model.threads.first { $0.id == id })
        XCTAssertEqual(thread.mood, .needsYou)
        XCTAssertFalse(thread.isSnoozed)
        XCTAssertEqual(model.workingCount, 2)
        XCTAssertTrue(model.needsAttention)
        XCTAssertTrue(model.prompts.allSatisfy { $0.threadId == id })
        XCTAssertEqual(model.allCards.first { $0.id == id }?.state, .needsYou)
    }

    private func assertHasAPromptFor(_ model: T3IsleModel, _ id: String) async throws {
        try await until { model.prompts.contains { $0.threadId == id } }
        XCTAssertEqual(Set(model.prompts.map(\.requestId)), ["\(id)-req-cmd", "\(id)-req-q"])
    }

    private func assertHiddenAgain(_ model: T3IsleModel, _ id: String) async throws {
        try await until { !shownIds(model).contains(id) && model.detail(for: id) == nil }
        XCTAssertTrue(model.prompts.isEmpty)
        XCTAssertEqual(model.workingCount, 2)
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

    func testHiddenSubagentShowsInWaitingOnYouOnlyWhileItAsks() async throws {
        let model = try await model()
        XCTAssertFalse(shownIds(model).contains("t-subagent"))
        try ask("t-subagent")
        try await assertHasAPromptFor(model, "t-subagent")
        try assertWaitingOnYouOnly(model, "t-subagent")
        try resolve("t-subagent")
        try await assertHiddenAgain(model, "t-subagent")
        model.stop()
    }

    func testHiddenSideChatShowsInWaitingOnYouOnlyWhileItAsks() async throws {
        let model = try await model()
        XCTAssertFalse(shownIds(model).contains("t-side-chat"))
        try ask("t-side-chat")
        try await assertHasAPromptFor(model, "t-side-chat")
        try assertWaitingOnYouOnly(model, "t-side-chat")
        try resolve("t-side-chat")
        try await assertHiddenAgain(model, "t-side-chat")
        model.stop()
    }

    func testOpeningAnAskingSubagentOpensThatThread() async throws {
        let model = try await model()
        try ask("t-subagent")
        try await assertHasAPromptFor(model, "t-subagent")
        let prompt = try XCTUnwrap(model.prompts.first)
        model.open(prompt.threadId)
        try await until { !opened.isEmpty }
        XCTAssertEqual(opened.map(\.absoluteString), ["t3code://threads/env-local/t-subagent"])
        model.stop()
    }

    func testShowSubagentsSettingStillShowsWorkingSubagentsAndAskingSideChats() async throws {
        let model = try await model()
        model.apply(T3Preferences(showSubagents: true))
        try ask("t-side-chat")
        try await assertHasAPromptFor(model, "t-side-chat")
        XCTAssertEqual(model.threads.first { $0.id == "t-subagent" }?.mood, .working)
        XCTAssertEqual(model.threads.first { $0.id == "t-side-chat" }?.mood, .needsYou)
        try resolve("t-side-chat")
        try await until { !shownIds(model).contains("t-side-chat") }
        XCTAssertTrue(shownIds(model).contains("t-subagent"))
        model.stop()
    }
}
