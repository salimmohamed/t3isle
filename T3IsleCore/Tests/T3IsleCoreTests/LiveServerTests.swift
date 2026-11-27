import XCTest
@testable import T3IsleCore

private func liveTokenStore() throws -> MemoryTokenStore {
    guard let token = ProcessInfo.processInfo.environment["T3ISLE_TOKEN"], !token.isEmpty else {
        throw XCTSkip("Set T3ISLE_TOKEN to run against a live T3 server.")
    }
    return MemoryTokenStore(StoredToken(token: token, expiresAt: .distantFuture))
}

final class LiveServerTests: XCTestCase {
    private func liveClient() throws -> T3ServerClient {
        let store = try liveTokenStore()
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
    func testModelGoesLiveWithThreadsInFirstSnapshot() async throws {
        let store = try liveTokenStore()
        let source = SnapshotRecorder(LiveSource(tokenStore: store))
        let model = T3IsleModel(source: source, opener: { _ in })
        model.start()
        defer { model.stop() }
        await until(model) { model.connection != .connecting }
        XCTAssertNil(source.unreadable)
        XCTAssertEqual(model.connection, .live)
        let snapshot = try XCTUnwrap(source.firstSnapshot)
        XCTAssertFalse(snapshot.threads.isEmpty)
    }
}

private final class SnapshotRecorder: T3Source, @unchecked Sendable {
    private let base: T3Source
    private let lock = NSLock()
    private var recorded: ShellSnapshot?
    private var rejected: String?

    init(_ base: T3Source) {
        self.base = base
    }

    var firstSnapshot: ShellSnapshot? { lock.withLock { recorded } }

    var unreadable: String? { lock.withLock { rejected } }

    func updates() async -> AsyncStream<ShellUpdate> {
        let upstream = await base.updates()
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        let forward = Task {
            for await update in upstream {
                record(update)
                continuation.yield(update)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forward.cancel() }
        return stream
    }

    private func record(_ update: ShellUpdate) {
        lock.withLock {
            switch update {
            case .snapshot(let snapshot) where recorded == nil: recorded = snapshot
            case .unreadable(let item, let reason) where rejected == nil: rejected = "\(item.rawValue): \(reason)"
            default: break
            }
        }
    }

    func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        try await base.detail(threadId: threadId, in: environment)
    }

    func send(_ command: T3Command, in environment: String?) async throws {
        try await base.send(command, in: environment)
    }

    func linked() async -> LinkedRead? { await base.linked() }
    func environmentId() async -> String? { await base.environmentId() }
    func providers() -> [ProviderLimits] { base.providers() }
}
