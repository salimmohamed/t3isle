import Foundation
import Network
@testable import T3IsleCore

extension T3Home {
    static func local(port: UInt16) throws -> T3Home {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let userdata = root.appendingPathComponent("userdata")
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        let runtime = #"{"origin":"http://127.0.0.1:\#(port)"}"#
        try Data(runtime.utf8).write(to: userdata.appendingPathComponent("server-runtime.json"))
        return T3Home(root: root)
    }
}

final class LocalListener: @unchecked Sendable {
    enum StartError: Error {
        case alreadyStarted
    }

    private enum Readiness {
        case idle
        case waiting(owner: UUID, CheckedContinuation<Void, Error>)
        case settled(owner: UUID)
    }

    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var readiness = Readiness.idle

    init(label: String, parameters: NWParameters = .tcp) throws {
        listener = try NWListener(using: parameters, on: .any)
        queue = DispatchQueue(label: label)
    }

    deinit {
        listener.cancel()
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    func start(accepting accept: @escaping @Sendable (NWConnection) -> Void) async throws {
        let queue = queue
        let listener = listener
        let caller = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard claim(continuation, for: caller) else { return }
                listener.stateUpdateHandler = { [weak self] state in self?.changed(state) }
                listener.newConnectionHandler = { connection in
                    connection.start(queue: queue)
                    accept(connection)
                }
                listener.start(queue: queue)
            }
        } onCancel: {
            if owns(caller) { listener.cancel() }
        }
    }

    private func owns(_ caller: UUID) -> Bool {
        lock.withLock {
            switch readiness {
            case .idle: false
            case .waiting(let owner, _), .settled(let owner): owner == caller
            }
        }
    }

    private func claim(_ continuation: CheckedContinuation<Void, Error>, for caller: UUID) -> Bool {
        enum Claim { case claimed, taken, cancelled }
        let claim: Claim = lock.withLock {
            guard case .idle = readiness else { return .taken }
            readiness = .waiting(owner: caller, continuation)
            return Task.isCancelled ? .cancelled : .claimed
        }
        switch claim {
        case .claimed: return true
        case .taken: continuation.resume(throwing: StartError.alreadyStarted)
        case .cancelled: changed(.cancelled)
        }
        return false
    }

    private func changed(_ state: NWListener.State) {
        let result: Result<Void, Error>
        switch state {
        case .ready: result = .success(())
        case .failed(let error): result = .failure(error)
        case .cancelled: result = .failure(CancellationError())
        default: return
        }
        let waiter: CheckedContinuation<Void, Error>? = lock.withLock {
            guard case .waiting(let owner, let continuation) = readiness else { return nil }
            readiness = .settled(owner: owner)
            return continuation
        }
        waiter?.resume(with: result)
    }
}
