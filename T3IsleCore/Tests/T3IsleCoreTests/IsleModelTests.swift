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
        await until(model) { model.connection == .live }
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
    private let opening: [ShellUpdate]
    private var details: [String: ThreadProjection]
    var projections: [String: ThreadProjection] {
        get { lock.withLock { details } }
        set { lock.withLock { details = newValue } }
    }
    private var continuation: AsyncStream<ShellUpdate>.Continuation?

    init(_ snapshot: ShellSnapshot, projections: [String: ThreadProjection] = [:]) {
        opening = [.snapshot(snapshot)]
        details = projections
    }

    init(opening: [ShellUpdate]) {
        self.opening = opening
        details = [:]
    }

    func push(_ update: ShellUpdate) {
        continuation?.yield(update)
    }

    func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        self.continuation = continuation
        for update in opening { continuation.yield(update) }
        return stream
    }

    func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        if let environment {
            lock.withLock { environments[threadId] = environment }
            linkedDetailRead.yield(threadId)
        }
        guard let projection = projections[threadId] else { throw CancellationError() }
        return projection
    }

    var limits: [ProviderLimits] = []
    private var read: LinkedRead? = LinkedRead()
    var linkedRead: LinkedRead? {
        get { lock.withLock { read } }
        set { lock.withLock { read = newValue } }
    }
    private let lock = NSLock()
    private var environments: [String: String] = [:]
    var detailEnvironments: [String: String] { lock.withLock { environments } }
    let (linkedCalls, linkedCalled) = AsyncStream<Void>.makeStream()
    let (linkedDetailReads, linkedDetailRead) = AsyncStream<String>.makeStream()
    let (sends, sending) = AsyncStream<String?>.makeStream()

    func send(_ command: T3Command, in environment: String?) async throws {
        sending.yield(environment)
    }

    func linked() async -> LinkedRead? {
        defer { linkedCalled.yield() }
        return linkedRead
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
final class UnreadableSnapshotTests: XCTestCase {
    func testUnreadableSnapshotTakesTheModelOffline() async throws {
        let broken: [String: Any] = ["kind": "snapshot", "snapshot": ["snapshotSequence": 1, "threads": [] as [Any]]]
        let updates = T3ServerClient.shellUpdates(broken)
        guard case .unreadable(.snapshot, let reason)? = updates.first else {
            return XCTFail("unreadable snapshot expected, got \(updates)")
        }
        XCTAssertTrue(reason.contains("projects"), reason)
        let model = T3IsleModel(source: FixtureSource(opening: updates), clock: TestClock(), opener: { _ in })
        model.start()
        await until(model) { model.connection != .connecting }
        XCTAssertEqual(model.connection, .offline(T3Failure.unreadable.localizedDescription))
        model.stop()
    }

    func testUnreadableThreadUpdateKeepsTheModelLive() async throws {
        let source = FixtureSource(ShellSnapshot(threads: [], projects: []))
        let model = T3IsleModel(source: source, clock: TestClock(), opener: { _ in })
        model.start()
        await until(model) { model.connection == .live }
        let fixture = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let shell = try XCTUnwrap(fixture.threads.first { !$0.isSubagent && !$0.isSideChat })
        source.push(.unreadable(.threadUpdated, reason: "missing title"))
        source.push(.threadUpdated(shell, archived: false))
        await until(model) { !model.threads.isEmpty }
        XCTAssertEqual(model.connection, .live)
        model.stop()
    }
}

@MainActor
final class IdlePresenceTests: XCTestCase {
    private func started(with threads: [ThreadShell]) -> (T3IsleModel, FixtureSource) {
        let source = FixtureSource(ShellSnapshot(threads: threads, projects: []))
        let model = T3IsleModel(source: source, clock: TestClock(), opener: { _ in })
        model.start()
        return (model, source)
    }

    func testNothingShowsBeforeTheFirstSnapshot() {
        let (model, _) = started(with: [])
        XCTAssertEqual(model.connection, .connecting)
        XCTAssertEqual(model.closedPresence, .none)
        model.stop()
    }

    func testConnectedWithNoThreadsIsIdle() async {
        let (model, _) = started(with: [])
        await until(model) { model.connection == .live }
        XCTAssertEqual(model.closedPresence, .idle)
        model.stop()
    }

    func testConnectedWithOnlyHiddenSubagentsIsIdle() async throws {
        let snapshot = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let subagents = snapshot.threads.filter(\.isSubagent)
        XCTAssertFalse(subagents.isEmpty)
        let (model, _) = started(with: subagents)
        await until(model) { model.connection == .live }
        XCTAssertTrue(model.threads.isEmpty)
        XCTAssertEqual(model.closedPresence, .idle)
        model.stop()
    }

    func testDisconnectingClearsIdle() async {
        let (model, source) = started(with: [])
        await until(model) { model.closedPresence == .idle }
        source.push(.disconnected(.notRunning))
        await until(model) { model.connection != .live }
        XCTAssertEqual(model.closedPresence, .none)
        model.stop()
    }

    func testDisconnectingHidesThreadsLeftFromBeforeTheDisconnect() async throws {
        let snapshot = try WireDecoder.make().decode(ShellSnapshot.self, from: Fixture.data("shell.json"))
        let (model, source) = started(with: snapshot.threads)
        await until(model) { !model.threads.isEmpty }
        XCTAssertNotEqual(model.closedPresence, .none)
        source.push(.disconnected(.notRunning))
        await until(model) { model.connection != .live }
        XCTAssertFalse(model.threads.isEmpty)
        XCTAssertEqual(model.closedPresence, .none)
        model.stop()
    }

    func testDisablingClearsIdle() async {
        let (model, _) = started(with: [])
        await until(model) { model.closedPresence == .idle }
        model.apply(T3Preferences(enabled: false))
        XCTAssertEqual(model.closedPresence, .none)
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

    private func wslRead(questionStatus: String = "waiting") throws -> LinkedRead {
        let threads = try LinkedFixtures.threads(in: wsl).map { shell in
            var shell = shell
            if shell.id == "wsl-question" { shell.status = questionStatus }
            return shell
        }
        return LinkedRead(reachable: [wsl.id], answered: [wsl.id], threads: threads, projects: try LinkedFixtures.projects())
    }

    private func nextRefresh(_ calls: inout AsyncStream<Void>.Iterator) async {
        await clock.waitForSleepers()
        clock.advance(by: T3IsleModel.linkedInterval)
        await calls.next()
    }

    private func model(_ source: FixtureSource) -> T3IsleModel {
        let model = T3IsleModel(source: source, clock: clock, opener: { [opening] url in opening.yield(url) })
        model.start()
        return model
    }

    func testLinkedThreadsJoinLocalOnesWithTheirMachineLabel() async throws {
        let source = try source()
        source.linkedRead = try wslRead()
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
        source.linkedRead = try wslRead()
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
        model.open("t-working")
        let local = await urls.next()
        XCTAssertEqual(local?.absoluteString, "t3code://threads/env-local/t-working")
        model.stop()
    }

    func testAClosedNotchReadsDetailOnlyForTheLinkedThreadThatNeedsYou() async throws {
        let source = try source()
        source.linkedRead = try wslRead()
        let model = model(source)
        var calls = source.linkedCalls.makeAsyncIterator()
        var reads = source.linkedDetailReads.makeAsyncIterator()
        await calls.next()
        let first = await reads.next()
        XCTAssertEqual(first, "wsl-question")

        await nextRefresh(&calls)
        let second = await reads.next()
        XCTAssertEqual(second, "wsl-question")

        model.expanded = true
        let shown = await reads.next()
        XCTAssertEqual(shown, "wsl-watching")
        model.stop()
    }

    func testClosingTheNotchForgetsDetailOfLinkedThreadsThatNoLongerNeedIt() async throws {
        let source = try source()
        var watching = try XCTUnwrap(source.projections["wsl-question"])
        watching.thread.id = "wsl-watching"
        source.projections["wsl-watching"] = watching
        source.linkedRead = try wslRead()
        let model = model(source)
        await until(model) { model.detail(for: "wsl-question") != nil }

        model.expanded = true
        await until(model) { model.detail(for: "wsl-watching") != nil }
        model.expanded = false

        XCTAssertNil(model.detail(for: "wsl-watching"))
        XCTAssertNotNil(model.detail(for: "wsl-question"))
        model.stop()
    }

    func testAnAnsweredLinkedQuestionDoesNotComeBackWithTheNextOne() async throws {
        let source = try source()
        source.linkedRead = try wslRead()
        let model = model(source)
        var calls = source.linkedCalls.makeAsyncIterator()
        await until(model) { model.prompts.contains { $0.threadId == "wsl-question" } }

        source.projections = [:]
        source.linkedRead = try wslRead(questionStatus: "running")
        await nextRefresh(&calls)
        await until(model) { model.threads.first { $0.id == "wsl-question" }?.mood == .working }

        source.linkedRead = try wslRead()
        await nextRefresh(&calls)
        await until(model) { model.threads.first { $0.id == "wsl-question" }?.mood == .needsYou }
        XCTAssertFalse(model.prompts.contains { $0.threadId == "wsl-question" })
        model.stop()
    }

    func testAnUnreachableLinkLeavesLocalThreadsAndIsRetriedOnTheNextRefresh() async throws {
        let source = try source()
        let model = model(source)
        var calls = source.linkedCalls.makeAsyncIterator()
        await calls.next()
        await until(model) { model.threads.contains { $0.id == "t-working" } }
        XCTAssertFalse(model.threads.contains { $0.environment != nil })

        source.linkedRead = try wslRead()
        await nextRefresh(&calls)
        await until(model) { model.threads.contains { $0.id == "wsl-replied" } }
        XCTAssertTrue(model.threads.contains { $0.id == "t-working" })
        model.stop()
    }

    func testAFailedReadKeepsTheRowsItCouldNotRefresh() async throws {
        let source = try source()
        source.linkedRead = try wslRead()
        let model = model(source)
        var calls = source.linkedCalls.makeAsyncIterator()
        await calls.next()
        await until(model) { model.threads.contains { $0.id == "wsl-replied" } }

        source.linkedRead = nil
        await nextRefresh(&calls)
        source.linkedRead = LinkedRead(reachable: [wsl.id])
        await nextRefresh(&calls)
        XCTAssertEqual(model.threads.first { $0.id == "wsl-replied" }?.project, "deploy-tools")

        source.linkedRead = LinkedRead()
        await nextRefresh(&calls)
        await until(model) { !model.threads.contains { $0.environment != nil } }
        model.stop()
    }
}
