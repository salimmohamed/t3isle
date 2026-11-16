import XCTest
@testable import T3IsleCore

final class DebugCommandTests: XCTestCase {
    func testParsesEveryCommandFromTokens() throws {
        let cases: [([String], DebugCommand)] = [
            (["open-settings"], .openSettings(pane: nil)),
            (["open-settings", "t3"], .openSettings(pane: "t3")),
            (["open-notch"], .openNotch),
            (["close-notch"], .closeNotch),
            (["tab", "Shelf"], .tab(.shelf)),
            (["demo", "on"], .demo(true)),
            (["demo", "off"], .demo(false)),
            (["question"], .question),
            (["plan-done"], .planDone),
            (["airpods-connect"], .airpodsConnect(name: "AirPods Pro", battery: nil)),
            (["airpods-connect", "AirPods Max"], .airpodsConnect(name: "AirPods Max", battery: nil)),
            (["airpods-connect", "AirPods Max", "64"], .airpodsConnect(name: "AirPods Max", battery: 64)),
            (["airpods-disconnect"], .airpodsDisconnect),
        ]
        for (tokens, expected) in cases {
            XCTAssertEqual(try DebugCommand.parse(tokens), expected, "\(tokens)")
        }
        XCTAssertEqual(Set(cases.map { $0.0[0] }), Set(DebugCommand.specs.map(\.name)))
    }

    func testRejectsUnknownCommandsAndBadArguments() {
        XCTAssertThrowsError(try DebugCommand.parse([])) { XCTAssertEqual($0 as? DebugCommandError, .empty) }
        XCTAssertThrowsError(try DebugCommand.parse(["dance"])) { XCTAssertEqual($0 as? DebugCommandError, .unknown("dance")) }
        let bad: [([String], String)] = [
            (["tab", "calendar"], "tab home|shelf|t3"),
            (["demo"], "demo on|off"),
            (["question", "now"], "question"),
            (["airpods-connect", "AirPods", "120"], "airpods-connect [name] [battery]"),
            (["airpods-connect", "AirPods", "full"], "airpods-connect [name] [battery]"),
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
            ("t3isle-debug://airpods-connect/AirPods%20Max/42", .airpodsConnect(name: "AirPods Max", battery: 42)),
            ("T3ISLE-DEBUG://plan-done/", .planDone),
            ("t3isle-debug:///question", .question),
        ]
        for (string, expected) in urls {
            XCTAssertEqual(try DebugCommand.parse(url: try XCTUnwrap(URL(string: string))), expected, string)
        }
        XCTAssertThrowsError(try DebugCommand.parse(url: try XCTUnwrap(URL(string: "https://question"))))
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
                         "--debug", "open-settings", "t3", "--demo", "--debug", "question", "--debug", "tab", "t3"]
        XCTAssertEqual(try DebugCommand.launchCommands(arguments), [.openSettings(pane: "t3"), .question, .tab(.t3)])
        XCTAssertEqual(try DebugCommand.launchCommands(["T3 Isle", "--demo"]), [])
    }
}

@MainActor
final class DebugSourceTests: XCTestCase {
    private func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func started() async throws -> (T3IsleModel, DebugSource) {
        let source = DebugSource(base: EmptySource())
        let model = T3IsleModel(source: source, opener: { _ in })
        model.start()
        try await until { model.connection == .live }
        return (model, source)
    }

    func testQuestionAsksForAttentionAndAnsweringClearsIt() async throws {
        let (model, source) = try await started()
        let id = source.raiseQuestion()
        try await until { model.needsAttention }
        let prompt = try XCTUnwrap(model.prompts.first)
        XCTAssertEqual(prompt.threadId, id)
        XCTAssertEqual(model.closedPresence, .alert)
        XCTAssertEqual(model.threads.first?.mood, .needsYou)
        model.answer(prompt, with: .choices(["Yes"]))
        try await until { !model.needsAttention && model.threads.first?.mood != .needsYou }
        model.stop()
    }

    func testPlanDoneShowsTheBanner() async throws {
        let (model, source) = try await started()
        let id = source.finishPlan(after: .milliseconds(600))
        try await until { model.banner != nil }
        XCTAssertEqual(model.banner?.threadId, id)
        XCTAssertEqual(model.banner?.stepCount, 3)
        model.stop()
    }

    func testFakeThreadsSurviveAReconnectSnapshot() async throws {
        let base = EmptySource()
        let source = DebugSource(base: base)
        let model = T3IsleModel(source: source, opener: { _ in })
        model.start()
        try await until { model.connection == .live }
        let id = source.raiseQuestion()
        try await until { model.needsAttention }
        base.push(.snapshot(ShellSnapshot(threads: [], projects: [])))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(model.prompts.first?.threadId, id)
        model.stop()
    }
}

private final class EmptySource: T3Source, @unchecked Sendable {
    private var continuation: AsyncStream<ShellUpdate>.Continuation?

    func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        self.continuation = continuation
        continuation.yield(.snapshot(ShellSnapshot(threads: [], projects: [])))
        return stream
    }

    func push(_ update: ShellUpdate) { continuation?.yield(update) }
    func detail(threadId: String) async throws -> ThreadProjection { throw T3Failure.http(404, "Thread not found") }
    func send(_ command: T3Command) async throws {}
    func environmentId() async -> String? { nil }
    func providers() -> [ProviderLimits] { [] }
}
