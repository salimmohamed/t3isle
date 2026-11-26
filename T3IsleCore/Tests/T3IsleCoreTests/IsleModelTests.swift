import Combine
import XCTest
@testable import T3IsleCore

@MainActor
final class IsleModelTests: XCTestCase {
    private let clock = TestClock()

    private func startedModel() async throws -> T3IsleModel {
        let source = ReplaySource(scenario: try Scenario.named("showcase"), clock: clock)
        let model = T3IsleModel(source: source, isDemo: true, clock: clock, opener: { _ in })
        model.start()
        await until(model) { model.prompts.count >= 4 }
        return model
    }

    private func updatedAt(_ threadId: String, in model: T3IsleModel) -> Date? {
        model.threads.first { $0.id == threadId }?.updatedAt
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
        let sent = updatedAt(approval.threadId, in: model)
        model.respond(approval, decision: .accept)
        XCTAssertEqual(model.prompts.count, before - 1)
        XCTAssertFalse(model.prompts.contains { $0.id == approval.id })
        await until(model) { updatedAt(approval.threadId, in: model) != sent }
        XCTAssertFalse(model.prompts.contains { $0.id == approval.id })
        model.stop()
    }

    func testMultiQuestionRequestSubmitsAfterLastAnswer() async throws {
        let model = try await startedModel()
        let questions = model.prompts.filter { !$0.isApproval }
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions.map(\.title), ["Retries", "Backoff"])
        let sent = updatedAt(questions[0].threadId, in: model)
        model.answer(questions[0], with: .choices(["5xx"]))
        XCTAssertEqual(model.prompts.filter { !$0.isApproval }.map(\.id), [questions[1].id])
        model.answer(questions[1], with: .text("2 minutes"))
        XCTAssertTrue(model.prompts.filter { !$0.isApproval }.isEmpty)
        await until(model) { updatedAt(questions[0].threadId, in: model) != sent }
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

    func testClosedPresenceIsAlertWhileQuestionsWait() async throws {
        let model = try await startedModel()
        XCTAssertEqual(model.closedPresence, .alert)
        model.stop()
    }

    func testClosedPresenceClearsWhenDisabled() async throws {
        let model = try await startedModel()
        let (observed, seen) = AsyncStream<ClosedPresence>.makeStream()
        let observer = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { seen.yield(model.closedPresence) }
        model.apply(T3Preferences(enabled: false))
        _ = await observed.first { $0 == ClosedPresence.none }
        XCTAssertEqual(model.closedPresence, .none)
        observer.cancel()
        model.apply(T3Preferences(enabled: true))
        XCTAssertEqual(model.closedPresence, .alert)
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

    func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        if let environment { detailEnvironments[threadId] = environment }
        guard let projection = projections[threadId] else { throw CancellationError() }
        return projection
    }

    var limits: [ProviderLimits] = []
    var linkedSnapshot = ShellSnapshot(threads: [], projects: [])
    private(set) var detailEnvironments: [String: String] = [:]
    let (linkedCalls, linkedCalled) = AsyncStream<Void>.makeStream()
    let (sends, sending) = AsyncStream<String?>.makeStream()

    func send(_ command: T3Command, in environment: String?) async throws {
        sending.yield(environment)
    }

    func linked() async -> ShellSnapshot {
        defer { linkedCalled.yield() }
        return linkedSnapshot
    }
    func environmentId() async -> String? { "env-local" }
    func providers() -> [ProviderLimits] { limits }
    func signOut() async {}
}

@MainActor
final class ProviderRefreshTests: XCTestCase {
    func testASnapshotRefreshesUsageLimitsWithoutWaitingForATick() async throws {
        let snapshot = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let source = FixtureSource(ShellSnapshot(threads: [], projects: snapshot.projects))
        let model = T3IsleModel(source: source, clock: TestClock(), opener: { _ in })
        model.start()
        await until(model) { model.connection == .live }
        XCTAssertEqual(model.providers, [])
        let limits = try XCTUnwrap(UsageLimitsReader.parse(Fixture.data("provider-claude.json"), id: "claudeAgent", previous: []))
        source.limits = [limits]
        source.push(.snapshot(snapshot))
        await until(model) { !model.threads.isEmpty }
        XCTAssertEqual(model.providers, [limits])
        model.stop()
    }
}

@MainActor
final class SubagentVisibilityTests: XCTestCase {
    private var snapshot: ShellSnapshot!
    private var source: FixtureSource!
    private let clock = TestClock()
    private let (opened, opening) = AsyncStream<URL>.makeStream()

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
        let model = T3IsleModel(source: source, clock: clock, opener: { [opening] url in opening.yield(url) })
        model.start()
        await until(model) { !model.threads.isEmpty }
        return model
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
        await until(model) { model.prompts.contains { $0.threadId == id } }
        XCTAssertEqual(Set(model.prompts.map(\.requestId)), ["\(id)-req-cmd", "\(id)-req-q"])
    }

    private func assertHiddenAgain(_ model: T3IsleModel, _ id: String) async throws {
        await until(model) { !shownIds(model).contains(id) }
        XCTAssertTrue(model.prompts.isEmpty)
        XCTAssertEqual(model.workingCount, 2)
        clock.advance(by: 2)
        await until(model) { model.detail(for: id) == nil }
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
        let url = await opened.first { _ in true }
        XCTAssertEqual(url?.absoluteString, "t3code://threads/env-local/t-subagent")
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
        await until(model) { !shownIds(model).contains("t-side-chat") }
        XCTAssertTrue(shownIds(model).contains("t-subagent"))
        model.stop()
    }
}

@MainActor
final class LinkedEnvironmentModelTests: XCTestCase {
    private let clock = TestClock()
    private let wsl = LinkedEnvironment(id: "env-wsl", label: "WSL")
    private let (opened, opening) = AsyncStream<URL>.makeStream()

    private func source() throws -> FixtureSource {
        let local = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let remoteDetail = try T3ServerClient.relaySnapshot(LinkedFixtures.chunkValues("linked-detail.json"))
        return FixtureSource(local, projections: ["wsl-question": remoteDetail])
    }

    private func wslSnapshot() throws -> ShellSnapshot {
        ShellSnapshot(threads: try LinkedFixtures.threads(in: wsl), projects: try LinkedFixtures.projects())
    }

    private func model(_ source: FixtureSource) -> T3IsleModel {
        let model = T3IsleModel(source: source, clock: clock, opener: { [opening] url in opening.yield(url) })
        model.start()
        return model
    }

    func testLinkedThreadsJoinLocalOnesWithTheirMachineLabel() async throws {
        let source = try source()
        source.linkedSnapshot = try wslSnapshot()
        let model = model(source)
        await until(model) { model.threads.contains { $0.id == "wsl-replied" } && model.threads.contains { $0.id == "t-working" } }

        let remote = try XCTUnwrap(model.threads.first { $0.id == "wsl-replied" })
        XCTAssertEqual(remote.environment, wsl)
        XCTAssertEqual(remote.project, "deploy-tools")
        XCTAssertEqual(remote.mood, .replied)
        XCTAssertNil(model.threads.first { $0.id == "t-working" }?.environment)
        XCTAssertFalse(model.threads.contains { $0.id == "thread:delegated-task:review" })
        XCTAssertFalse(model.allCards.contains { $0.id == "thread:delegated-task:review" })
        model.stop()
    }

    func testAQuestionOnALinkedThreadReadsAndAnswersThroughItsEnvironment() async throws {
        let source = try source()
        source.linkedSnapshot = try wslSnapshot()
        let model = model(source)
        await until(model) { model.prompts.contains { $0.threadId == "wsl-question" } }

        XCTAssertEqual(model.threads.first { $0.id == "wsl-question" }?.mood, .needsYou)
        XCTAssertEqual(source.detailEnvironments["wsl-question"], "env-wsl")
        let questions = model.prompts.filter { $0.threadId == "wsl-question" && !$0.isApproval }
        XCTAssertFalse(questions.isEmpty)
        for question in questions { model.answer(question, with: .text("5 retries")) }
        var sends = source.sends.makeAsyncIterator()
        let environment = await sends.next()
        XCTAssertEqual(environment, "env-wsl")
        model.open("wsl-replied")
        var urls = opened.makeAsyncIterator()
        let url = await urls.next()
        XCTAssertEqual(url?.absoluteString, "t3code://threads/env-wsl/wsl-replied")
        model.stop()
    }

    func testAnUnreachableLinkLeavesLocalThreadsAndIsRetriedOnTheNextRefresh() async throws {
        let source = try source()
        let model = model(source)
        var calls = source.linkedCalls.makeAsyncIterator()
        await calls.next()
        await until(model) { model.threads.contains { $0.id == "t-working" } }
        XCTAssertFalse(model.threads.contains { $0.environment != nil })

        source.linkedSnapshot = try wslSnapshot()
        await clock.waitForSleepers()
        clock.advance(by: T3IsleModel.linkedInterval)
        await calls.next()
        await until(model) { model.threads.contains { $0.id == "wsl-replied" } }
        XCTAssertTrue(model.threads.contains { $0.id == "t-working" })
        model.stop()
    }
}
