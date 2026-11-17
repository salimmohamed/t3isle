import Foundation
@testable import T3IsleCore

final class TestClock: T3Clock, @unchecked Sendable {
    private struct Sleeper {
        let id: Int
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Arrival {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var current: Date
    private var sleepers: [Sleeper] = []
    private var arrivals: [Arrival] = []
    private var lastId = 0

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = now
    }

    var now: Date { lock.withLock { current } }

    var deadlines: [Date] { lock.withLock { sleepers.map(\.deadline).sorted() } }

    func sleep(until deadline: Date) async throws {
        let id = lock.withLock {
            lastId += 1
            return lastId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                register(Sleeper(id: id, deadline: deadline, continuation: continuation))
            }
        } onCancel: {
            cancel(id)
        }
    }

    func advance(by seconds: TimeInterval) {
        let due: [Sleeper] = lock.withLock {
            current += seconds
            let due = sleepers.filter { $0.deadline <= current }.sorted { ($0.deadline, $0.id) < ($1.deadline, $1.id) }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    func waitForSleepers(_ count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready: Bool = lock.withLock {
                guard sleepers.count < count else { return true }
                arrivals.append(Arrival(count: count, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    private func register(_ sleeper: Sleeper) {
        enum Outcome { case cancelled, due, waiting([Arrival]) }
        let outcome: Outcome = lock.withLock {
            if Task.isCancelled { return .cancelled }
            if sleeper.deadline <= current { return .due }
            sleepers.append(sleeper)
            let ready = arrivals.filter { $0.count <= sleepers.count }
            arrivals.removeAll { $0.count <= sleepers.count }
            return .waiting(ready)
        }
        switch outcome {
        case .cancelled: sleeper.continuation.resume(throwing: CancellationError())
        case .due: sleeper.continuation.resume()
        case .waiting(let ready): for arrival in ready { arrival.continuation.resume() }
        }
    }

    private func cancel(_ id: Int) {
        let cancelled: Sleeper? = lock.withLock {
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
            return sleepers.remove(at: index)
        }
        cancelled?.continuation.resume(throwing: CancellationError())
    }
}
