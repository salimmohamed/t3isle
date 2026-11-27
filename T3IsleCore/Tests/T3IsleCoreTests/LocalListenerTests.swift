import Network
import XCTest

final class LocalListenerTests: XCTestCase {
    func testTwoStartsAtOnceStartTheListenerOnceAndRefuseTheOther() async throws {
        let listener = try LocalListener(label: "LocalListenerTests")
        async let first = Self.outcome { try await listener.start { $0.cancel() } }
        async let second = Self.outcome { try await listener.start { $0.cancel() } }
        let outcomes = await [first, second].sorted()

        XCTAssertEqual(outcomes, ["alreadyStarted", "ready"])
        XCTAssertNotEqual(listener.port, 0)
    }

    func testAStartCancelledBeforeTheListenerIsReadyEnds() async throws {
        let listener = try LocalListener(label: "LocalListenerTests")
        let start = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Self.outcome { try await listener.start { $0.cancel() } }
        }
        let outcome = await start.value
        XCTAssertEqual(outcome, "cancelled")
    }

    private static func outcome(_ start: () async throws -> Void) async -> String {
        do {
            try await start()
            return "ready"
        } catch LocalListener.StartError.alreadyStarted {
            return "alreadyStarted"
        } catch is CancellationError {
            return "cancelled"
        } catch {
            return String(describing: error)
        }
    }
}
