import XCTest
@testable import T3IsleCore

final class SignInTests: XCTestCase {
    func testSessionIsIssuedUnderTheGivenLabel() async throws {
        let runner = RecordingRunner()
        let home = T3Home(root: URL(fileURLWithPath: "/work/.t3"))
        let signIn = T3SignIn(home: home, store: MemoryTokenStore(), runner: runner, label: "T3 Isle Debug")

        _ = try await signIn.token()

        let arguments = try XCTUnwrap(runner.calls.first)
        let label = try XCTUnwrap(arguments.firstIndex(of: "--label"))
        XCTAssertEqual(arguments[label + 1], "T3 Isle Debug")
    }
}

private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []

    var calls: [[String]] { lock.withLock { recorded } }

    func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
        lock.withLock { recorded.append(arguments) }
        return Data(#"{"token":"secret","expiresAt":"2033-05-18T03:33:20.000Z"}"#.utf8)
    }
}
