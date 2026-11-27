import XCTest
@testable import T3IsleCore

final class DebugCommandTests: XCTestCase {
    private let everyCommand: [([String], DebugCommand)] = [
        (["open-settings"], .openSettings(pane: nil)),
        (["open-settings", "t3"], .openSettings(pane: "t3")),
        (["close-settings"], .closeSettings),
        (["open-notch"], .openNotch),
        (["close-notch"], .closeNotch),
        (["tab", "Shelf"], .tab(.shelf)),
        (["demo", "on"], .demo(true)),
        (["demo", "off"], .demo(false)),
        (["replay", "question"], .replay("question")),
        (["replay", "Plan-Done"], .replay("plan-done")),
        (["replay", "off"], .replayOff),
        (["state"], .state),
        (["airpods-connect"], .airpodsConnect(name: "AirPods Pro", battery: nil, device: nil)),
        (["airpods-connect", "AirPods Max"], .airpodsConnect(name: "AirPods Max", battery: nil, device: nil)),
        (["airpods-connect", "AirPods Max", "64"], .airpodsConnect(name: "AirPods Max", battery: 64, device: nil)),
        (["airpods-connect", "Pill", "SPEAKER"], .airpodsConnect(name: "Pill", battery: nil, device: .speaker)),
        (["airpods-connect", "My Car", "80", "car"], .airpodsConnect(name: "My Car", battery: 80, device: .car)),
        (["airpods-disconnect"], .airpodsDisconnect),
        (["bluetooth-access", "Denied"], .bluetoothAccess(.denied)),
        (["bluetooth-access", "not-determined"], .bluetoothAccess(.notDetermined)),
        (["bluetooth-access", "allowed"], .bluetoothAccess(.allowed)),
        (["bluetooth-access", "system"], .bluetoothAccess(nil)),
        (["accessibility-trust", "Trusted"], .accessibilityTrust(true)),
        (["accessibility-trust", "untrusted"], .accessibilityTrust(false)),
        (["accessibility-trust", "system"], .accessibilityTrust(nil)),
    ]

    func testParsesEveryCommandFromTokens() throws {
        for (tokens, expected) in everyCommand {
            XCTAssertEqual(try DebugCommand.parse(tokens), expected, "\(tokens)")
        }
        XCTAssertEqual(Set(everyCommand.map { $0.0[0] }), Set(DebugCommand.specs.map(\.name)))
    }

    func testEveryCommandButStateHasAReverseThatParses() throws {
        let readOnly: Set<String> = ["state"]
        for (tokens, command) in everyCommand {
            guard !readOnly.contains(tokens[0]) else {
                XCTAssertNil(command.reverse, "\(tokens) is read-only")
                continue
            }
            let reverse = try XCTUnwrap(command.reverse, "\(tokens) has no reverse")
            XCTAssertEqual(try DebugCommand.parse(reverse.tokens), reverse, "\(tokens)")
            XCTAssertEqual(try DebugCommand.parse(command.tokens), command, "\(tokens)")
        }
        XCTAssertEqual(DebugCommand.demo(true).reverse, .demo(false))
        XCTAssertEqual(DebugCommand.tab(.t3).reverse, .closeNotch)
        XCTAssertEqual(DebugCommand.replay("question").reverse, .replayOff)
        XCTAssertEqual(DebugCommand.openSettings(pane: "t3").reverse, .closeSettings)
        XCTAssertEqual(DebugCommand.bluetoothAccess(.allowed).reverse, .bluetoothAccess(nil))
        XCTAssertEqual(DebugCommand.accessibilityTrust(false).reverse, .accessibilityTrust(nil))
        XCTAssertEqual(DebugCommand.airpodsConnect(name: "AirPods Max", battery: 64, device: nil).line, "airpods-connect AirPods Max 64")
        XCTAssertEqual(DebugCommand.airpodsConnect(name: "Pill", battery: nil, device: .speaker).line, "airpods-connect Pill speaker")
    }

    func testRejectsUnknownCommandsAndBadArguments() {
        XCTAssertThrowsError(try DebugCommand.parse([])) { XCTAssertEqual($0 as? DebugCommandError, .empty) }
        XCTAssertThrowsError(try DebugCommand.parse(["dance"])) { XCTAssertEqual($0 as? DebugCommandError, .unknown("dance")) }
        XCTAssertThrowsError(try DebugCommand.parse(["question"])) { XCTAssertEqual($0 as? DebugCommandError, .unknown("question")) }
        let replayUsage = "replay busy-session|plan-done|question|quota-low|showcase|off"
        let airpodsUsage = "airpods-connect [name] [battery] [headphones|speaker|car]"
        let bad: [([String], String)] = [
            (["tab", "calendar"], "tab home|t3|shelf"),
            (["demo"], "demo on|off"),
            (["close-settings", "now"], "close-settings"),
            (["state", "now"], "state"),
            (["replay"], replayUsage),
            (["replay", "nope"], replayUsage),
            (["replay", "question", "twice"], replayUsage),
            (["airpods-connect", "AirPods", "120"], airpodsUsage),
            (["airpods-connect", "AirPods", "full"], airpodsUsage),
            (["airpods-connect", "AirPods", "car", "50"], airpodsUsage),
            (["airpods-connect", "AirPods", "50", "car", "car"], airpodsUsage),
            (["bluetooth-access"], "bluetooth-access not-determined|restricted|denied|allowed|system"),
            (["bluetooth-access", "granted"], "bluetooth-access not-determined|restricted|denied|allowed|system"),
            (["accessibility-trust"], "accessibility-trust trusted|untrusted|system"),
            (["accessibility-trust", "stale"], "accessibility-trust trusted|untrusted|system"),
        ]
        for (tokens, usage) in bad {
            XCTAssertThrowsError(try DebugCommand.parse(tokens)) { XCTAssertEqual($0 as? DebugCommandError, .usage(usage)) }
        }
    }

    func testParsesURLs() throws {
        let urls: [(String, DebugCommand)] = [
            ("t3isle-debug://open-settings", .openSettings(pane: nil)),
            ("t3isle-debug://open-settings/appearance", .openSettings(pane: "appearance")),
            ("t3isle-debug://tab/t3", .tab(.t3)),
            ("t3isle-debug://airpods-connect/AirPods%20Max/42", .airpodsConnect(name: "AirPods Max", battery: 42, device: nil)),
            ("t3isle-debug://airpods-connect/Dash/car", .airpodsConnect(name: "Dash", battery: nil, device: .car)),
            ("T3ISLE-DEBUG://replay/plan-done/", .replay("plan-done")),
            ("t3isle-debug:///replay/off", .replayOff),
        ]
        for (string, expected) in urls {
            XCTAssertEqual(try DebugCommand.parse(url: try XCTUnwrap(URL(string: string))), expected, string)
        }
        XCTAssertThrowsError(try DebugCommand.parse(url: try XCTUnwrap(URL(string: "https://replay/question"))))
    }

    func testURLQueryAndFragmentAreIgnored() throws {
        let plain = try DebugCommand.parse(url: try XCTUnwrap(URL(string: "t3isle-debug://replay/question")))
        for suffix in ["?n=3", "?n=3&x=y", "#n3", "?n=3#n3"] {
            let url = try XCTUnwrap(URL(string: "t3isle-debug://replay/question\(suffix)"))
            XCTAssertEqual(try DebugCommand.parse(url: url), plain, suffix)
        }
        XCTAssertEqual(try DebugCommand.parse(url: try XCTUnwrap(URL(string: "t3isle-debug://state?n=9"))), .state)
    }

    func testContributingDocumentsEveryCommand() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let guide = try String(contentsOf: root.appendingPathComponent("CONTRIBUTING.md"), encoding: .utf8)
        for spec in DebugCommand.specs {
            XCTAssertTrue(guide.contains("t3isle-debug://\(spec.name)"), "CONTRIBUTING.md has no example for \(spec.name)")
        }
    }

    func testCollectsLaunchArgumentCommands() throws {
        let arguments = ["/Applications/T3 Isle.app/Contents/MacOS/T3 Isle", "-NSDocumentRevisionsDebugMode", "YES",
                         "--debug", "open-settings", "t3", "--demo", "--debug", "replay", "question", "--debug", "tab", "t3"]
        XCTAssertEqual(try DebugCommand.launchCommands(arguments), [.openSettings(pane: "t3"), .replay("question"), .tab(.t3)])
        XCTAssertEqual(try DebugCommand.launchCommands(["T3 Isle", "--demo"]), [])
    }
}

@MainActor
final class DebugSourceTests: XCTestCase {
    private let clock = TestClock()

    private func started() async -> (T3IsleModel, DebugSource) {
        let source = DebugSource(base: BaseSource(finishedAt: clock.now), clock: clock)
        let model = T3IsleModel(source: source, clock: clock, opener: { _ in })
        model.start()
        await until(model) { model.threads.map(\.id) == ["base-thread"] }
        return (model, source)
    }

    private func switchTo(_ model: T3IsleModel, _ change: () -> Void) {
        change()
        model.restart()
    }

    private func finishPlan(_ model: T3IsleModel, _ source: DebugSource) async throws -> PlanBanner {
        let planDone = try Scenario.named("plan-done")
        switchTo(model) { source.play(planDone) }
        XCTAssertNil(model.banner)
        await until(model) { model.detail(for: "plan-thread")?.plan?.isComplete == false }
        clock.advance(by: 1.5)
        await until(model) { model.threads.first?.mood == .replied }
        XCTAssertNil(model.banner)
        clock.advance(by: 0.5)
        await until(model) { model.banner != nil }
        return try XCTUnwrap(model.banner)
    }

    func testReplayReplacesTheBaseWorldAndOffRestoresIt() async throws {
        let (model, source) = await started()
        let question = try Scenario.named("question")
        switchTo(model) { source.play(question) }
        await until(model) { model.needsAttention }
        XCTAssertTrue(source.isReplaying)
        XCTAssertEqual(model.threads.map(\.id), ["question-thread"])
        XCTAssertEqual(model.closedPresence, .alert)
        XCTAssertEqual(model.threads.first?.mood, .needsYou)

        switchTo(model) { source.stopReplay() }
        await until(model) { model.threads.map(\.id) == ["base-thread"] }
        XCTAssertFalse(source.isReplaying)
        XCTAssertNil(source.replay.current)
        XCTAssertFalse(model.needsAttention)
        model.stop()
    }

    func testAnsweringAReplayedQuestionClearsIt() async throws {
        let (model, source) = await started()
        let question = try Scenario.named("question")
        switchTo(model) { source.play(question) }
        await until(model) { model.needsAttention }
        let prompt = try XCTUnwrap(model.prompts.first)
        model.answer(prompt, with: .choices(["Yes"]))
        await until(model) { !model.needsAttention && model.threads.first?.mood == .working }
        XCTAssertEqual(model.threads.map(\.id), ["question-thread"])
        model.stop()
    }

    func testPlanDoneShowsTheBanner() async throws {
        let (model, source) = await started()
        let progress = source.replay.progress()
        let banner = try await finishPlan(model, source)
        XCTAssertEqual(banner.threadId, "plan-thread")
        XCTAssertEqual(banner.stepCount, 3)
        _ = await progress.first { $0 == .finished("plan-done") }
        XCTAssertEqual(source.replay.current, ReplayStatus(scenario: "plan-done", finished: true))
        model.stop()
    }

    func testReplayingPlanDoneAgainShowsANewBanner() async throws {
        let (model, source) = await started()
        let first = try await finishPlan(model, source)
        let second = try await finishPlan(model, source)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.threadId, "plan-thread")
        model.stop()
    }

    func testModelIsCaughtUpOnlyOnceItHasTakenInTheReplay() async throws {
        let source = ReplaySource(scenario: nil, clock: clock)
        let progress = source.progress()
        source.play(try Scenario.named("quota-low"))
        _ = await progress.first { $0 == .finished("quota-low") }
        let model = T3IsleModel(source: source, clock: clock, opener: { _ in })
        XCTAssertFalse(model.isCaughtUp(threads: source.threads, providers: source.providers()))
        model.start()
        await until(model) { model.isCaughtUp(threads: source.threads, providers: source.providers()) }
        XCTAssertEqual(model.threads.count, 2)
        XCTAssertEqual(model.providers.map(\.id), ["claudeAgent", "codex"])
        model.stop()
    }

    func testQuestionScenarioStateMatchesTheFixture() async throws {
        let source = ReplaySource(scenario: nil, clock: clock)
        let progress = source.progress()
        source.play(try Scenario.named("question"))
        let model = T3IsleModel(source: source, clock: clock, opener: { _ in })
        model.start()
        await until(model) { model.prompts.count == 1 }
        _ = await progress.first { $0 == .finished("question") }
        let expected = try JSONDecoder().decode(DebugState.T3.self, from: Fixture.data("debug-state-question.json"))
        XCTAssertEqual(model.debugState(enabled: true, source: .replay, replay: source.current), expected)
        model.stop()
    }

    func testReplayReportsProgressAndStreamsTheCurrentWorldFirst() async throws {
        let source = ReplaySource(scenario: nil, clock: clock)
        let progress = source.progress()
        source.play(try Scenario.named("question"))
        let events = await progress.prefix(2).reduce(into: []) { $0.append($1) }
        XCTAssertEqual(events, [.started("question", steps: 2), .finished("question")])
        XCTAssertEqual(source.current, ReplayStatus(scenario: "question", finished: true))

        var updates = await source.updates().makeAsyncIterator()
        guard case .snapshot(let snapshot)? = await updates.next() else { return XCTFail("expected a snapshot first") }
        XCTAssertEqual(snapshot.threads.map(\.id), ["question-thread"])
        let projection = try await source.detail(threadId: "question-thread", in: nil)
        XCTAssertEqual(projection.runtimeRequests.map(\.id), ["question-request"])
        let environment = await source.environmentId()
        XCTAssertEqual(environment, "replay")
    }
}

private final class BaseSource: T3Source, @unchecked Sendable {
    private let shell: ThreadShell

    init(finishedAt: Date) {
        shell = ThreadShell(id: "base-thread", projectId: "base", title: "Base thread", status: "completed",
                            latestRunCompletedAt: finishedAt, updatedAt: finishedAt)
    }

    func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        continuation.yield(.snapshot(ShellSnapshot(threads: [shell], projects: [ProjectShell(id: "base", title: "base")])))
        return stream
    }

    func detail(threadId: String, in environment: String?) async throws -> ThreadProjection { throw T3Failure.http(404, "Thread not found") }
    func send(_ command: T3Command, in environment: String?) async throws {}
    func linked() async -> LinkedRead? { LinkedRead() }
    func environmentId() async -> String? { nil }
    func providers() -> [ProviderLimits] { [] }
}
