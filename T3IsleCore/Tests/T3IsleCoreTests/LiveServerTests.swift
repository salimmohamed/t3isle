import XCTest
@testable import T3IsleCore

final class LiveServerTests: XCTestCase {
    private func liveClient() throws -> T3ServerClient {
        guard let token = ProcessInfo.processInfo.environment["T3ISLE_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set T3ISLE_TOKEN to run against a live T3 server.")
        }
        let store = MemoryTokenStore(StoredToken(token: token, expiresAt: Date().addingTimeInterval(3600)))
        let home = T3Home()
        return T3ServerClient(home: home, signIn: T3SignIn(home: home, store: store))
    }

    func testFetchesShellAndEnvironment() async throws {
        let client = try liveClient()
        let shell = try await client.shell()
        XCTAssertFalse(shell.projects.isEmpty)
        let environment = await client.environment()
        XCTAssertNotNil(environment)
        if let thread = shell.threads.first(where: { $0.latestRunId != nil }) {
            let detail = try await client.detail(threadId: thread.id)
            XCTAssertEqual(detail.thread.id, thread.id)
        }
    }

    func testStreamsShellSnapshot() async throws {
        let client = try liveClient()
        let stream = await client.shellUpdates()
        let first = try await withThrowingTaskGroup(of: ShellUpdate?.self) { group in
            group.addTask {
                for await update in stream { return update }
                return nil
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
        guard case .snapshot(let snapshot) = first else {
            return XCTFail("Expected a snapshot first, got \(String(describing: first))")
        }
        XCTAssertFalse(snapshot.threads.isEmpty)
        await client.disconnect()
    }
}
