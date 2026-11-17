import XCTest
@testable import T3IsleCore

final class LiveServerTests: XCTestCase {
    private func liveClient() throws -> T3ServerClient {
        guard let token = ProcessInfo.processInfo.environment["T3ISLE_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set T3ISLE_TOKEN to run against a live T3 server.")
        }
        let store = MemoryTokenStore(StoredToken(token: token, expiresAt: .distantFuture))
        let home = T3Home()
        return T3ServerClient(home: home, signIn: T3SignIn(home: home, store: store))
    }

    func testStreamsShellSnapshot() async throws {
        let client = try liveClient()
        var updates = await client.shellUpdates().makeAsyncIterator()
        let first = await updates.next()
        guard case .snapshot(let snapshot) = first else {
            return XCTFail("Expected a snapshot first, got \(String(describing: first))")
        }
        XCTAssertFalse(snapshot.threads.isEmpty)
        let environment = await client.environment()
        XCTAssertNotNil(environment)
        if let thread = snapshot.threads.first(where: { $0.latestRunId != nil }) {
            let detail = try await client.detail(threadId: thread.id)
            XCTAssertEqual(detail.thread.id, thread.id)
        }
        await client.disconnect()
    }
}

@MainActor
final class LiveModelTests: XCTestCase {
    func testModelListsLiveInbox() async throws {
        guard let token = ProcessInfo.processInfo.environment["T3ISLE_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set T3ISLE_TOKEN to run against a live T3 server.")
        }
        let store = MemoryTokenStore(StoredToken(token: token, expiresAt: .distantFuture))
        let model = T3IsleModel(source: LiveSource(tokenStore: store), opener: { _ in })
        model.start()
        await until(model) { model.connection != .connecting }
        XCTAssertEqual(model.connection, .live)
        XCTAssertFalse(model.threads.isEmpty)
        model.stop()
    }
}
