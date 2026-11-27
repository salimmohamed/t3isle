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
    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var readiness: CheckedContinuation<Void, Error>?

    init(label: String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        queue = DispatchQueue(label: label)
    }

    deinit {
        listener.cancel()
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    func start(accepting accept: @escaping @Sendable (NWConnection) -> Void) async throws {
        let queue = queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { readiness = continuation }
            listener.stateUpdateHandler = { [weak self] state in self?.changed(state) }
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    private func changed(_ state: NWListener.State) {
        let result: Result<Void, Error>
        switch state {
        case .ready: result = .success(())
        case .failed(let error): result = .failure(error)
        default: return
        }
        let waiter: CheckedContinuation<Void, Error>? = lock.withLock {
            defer { readiness = nil }
            return readiness
        }
        waiter?.resume(with: result)
    }
}
