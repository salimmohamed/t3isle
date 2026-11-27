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

    func testARefusedStartWhoseTaskIsCancelledLeavesTheRunningListenerAccepting() async throws {
        let (arrivals, arrived) = AsyncStream<String>.makeStream()
        let listener = try LocalListener(label: "LocalListenerTests")
        try await listener.start { connection in
            connection.cancel()
            arrived.yield("accepted")
        }
        let refused = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Self.outcome { try await listener.start { $0.cancel() } }
        }
        let refusal = await refused.value
        XCTAssertEqual(refusal, "alreadyStarted")

        let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: listener.port) ?? .any, using: .tcp)
        client.stateUpdateHandler = { state in
            switch state {
            case .waiting(let error), .failed(let error): arrived.yield("refused: \(error)")
            default: break
            }
        }
        client.start(queue: DispatchQueue(label: "LocalListenerTests.client"))
        var outcomes = arrivals.makeAsyncIterator()
        let arrival = await outcomes.next()
        client.cancel()
        XCTAssertEqual(arrival, "accepted")
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
