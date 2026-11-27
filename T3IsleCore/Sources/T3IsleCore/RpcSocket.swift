import Foundation

protocol RpcTransport: AnyObject {
    func resume()
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void)
    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
    func close()
}

extension URLSessionWebSocketTask: RpcTransport {
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) {
        send(.string(text), completionHandler: completion)
    }

    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        receive(completionHandler: completion)
    }

    func close() {
        cancel(with: .normalClosure, reason: nil)
    }
}

final class RpcSocket: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum Event {
        case chunk([Any])
        case exit(Result<Any?, T3Failure>)
    }

    static let pingInterval: TimeInterval = 5
    static let pongTimeout: TimeInterval = 10

    private let clock: any T3Clock
    private let lock = NSLock()
    private var transport: RpcTransport?
    private var session: URLSession?
    private var nextId = 1
    private var handlers: [String: (Event) -> Void] = [:]
    private var pings: Task<Void, Never>?
    private var unansweredPingSince: Date?
    private var closed = false
    private var onClose: (@Sendable (T3Failure) -> Void)?

    init(clock: any T3Clock = LiveClock()) {
        self.clock = clock
        super.init()
    }

    func connect(url: URL, token: String, onClose: @escaping @Sendable (T3Failure) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 64 * 1024 * 1024
        open(task, session: session, onClose: onClose)
    }

    func open(_ transport: RpcTransport, session: URLSession? = nil, onClose: @escaping @Sendable (T3Failure) -> Void) {
        lock.lock()
        self.session = session
        self.transport = transport
        self.onClose = onClose
        lock.unlock()
        transport.resume()
        receive()
        startPings()
    }

    func close() {
        finish(.notRunning, notify: false)
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    @discardableResult
    func request(_ tag: String, payload: [String: Any], handler: @escaping (Event) -> Void) -> String {
        request(tag, payload: payload) { _, event in handler(event) }
    }

    @discardableResult
    private func request(_ tag: String, payload: [String: Any], identified handler: @escaping (String, Event) -> Void) -> String {
        lock.lock()
        guard !closed else {
            lock.unlock()
            handler("", .exit(.failure(.notRunning)))
            return ""
        }
        let id = String(nextId)
        nextId += 1
        handlers[id] = { handler(id, $0) }
        lock.unlock()
        send(["_tag": "Request", "id": id, "tag": tag, "payload": payload, "headers": [] as [Any]])
        return id
    }

    func firstChunk(_ tag: String, payload: [String: Any]) async throws -> [Any] {
        try await withCheckedThrowingContinuation { continuation in
            request(tag, payload: payload) { id, event in
                switch event {
                case .chunk(let values):
                    if self.interrupt(id) { continuation.resume(returning: values) }
                case .exit(let result):
                    continuation.resume(with: result.map { _ in [] }.mapError { $0 as Error })
                }
            }
        }
    }

    private func interrupt(_ id: String) -> Bool {
        guard handler(for: id, remove: true) != nil else { return false }
        send(["_tag": "Interrupt", "requestId": id])
        return true
    }

    func call(_ tag: String, payload: [String: Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            request(tag, payload: payload) { event in
                if case .exit(let result) = event {
                    continuation.resume(with: result.mapError { $0 as Error })
                }
            }
        }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else { return }
        lock.lock()
        let transport = self.transport
        lock.unlock()
        transport?.send(text) { [weak self] error in
            if error != nil { self?.finish(.notRunning, notify: true) }
        }
    }

    private func receive() {
        lock.lock()
        let transport = self.transport
        lock.unlock()
        transport?.receive { [weak self] result in
            guard let self, !self.isClosed else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handle(Data(text.utf8))
                case .data(let data): self.handle(data)
                @unknown default: break
                }
                self.receive()
            case .failure:
                self.finish(.notRunning, notify: true)
            }
        }
    }

    private func handle(_ data: Data) {
        lock.withLock { unansweredPingSince = nil }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) else { return }
        let messages = (decoded as? [[String: Any]]) ?? [(decoded as? [String: Any]) ?? [:]]
        for message in messages { route(message) }
    }

    private func route(_ message: [String: Any]) {
        guard let tag = message["_tag"] as? String else { return }
        let requestId = Self.identifier(message["requestId"])
        switch tag {
        case "Chunk":
            guard let requestId else { return }
            send(["_tag": "Ack", "requestId": requestId])
            handler(for: requestId, remove: false)?(.chunk(message["values"] as? [Any] ?? []))
        case "Exit":
            guard let requestId else { return }
            handler(for: requestId, remove: true)?(.exit(Self.exitResult(message["exit"] as? [String: Any])))
        case "Defect":
            finish(.rejected("T3 closed the connection."), notify: true)
        default:
            break
        }
    }

    private func handler(for id: String, remove: Bool) -> ((Event) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return remove ? handlers.removeValue(forKey: id) : handlers[id]
    }

    static func identifier(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func exitResult(_ exit: [String: Any]?) -> Result<Any?, T3Failure> {
        guard let exit else { return .failure(.unreadable) }
        if exit["_tag"] as? String == "Success" { return .success(exit["value"]) }
        let causes = exit["cause"] as? [[String: Any]] ?? (exit["cause"] as? [String: Any]).map { [$0] } ?? []
        for cause in causes {
            if let error = cause["error"] as? [String: Any] {
                let message = error["message"] as? String ?? error["_tag"] as? String ?? "T3 refused."
                return .failure(.rejected(message))
            }
        }
        return .failure(.rejected("T3 refused."))
    }

    private func startPings() {
        let clock = self.clock
        let pings = Task { [weak self] in
            while true {
                do {
                    try await clock.sleep(until: clock.now.addingTimeInterval(Self.pingInterval))
                } catch {
                    return
                }
                guard let self, self.pingOrGiveUp() else { return }
            }
        }
        lock.withLock { self.pings = pings }
    }

    private func pingOrGiveUp() -> Bool {
        let now = clock.now
        lock.lock()
        if closed {
            lock.unlock()
            return false
        }
        if let since = unansweredPingSince, now.timeIntervalSince(since) >= Self.pongTimeout {
            lock.unlock()
            finish(.notRunning, notify: true)
            return false
        }
        if unansweredPingSince == nil { unansweredPingSince = now }
        lock.unlock()
        send(["_tag": "Ping"])
        return true
    }

    private func finish(_ failure: T3Failure, notify: Bool) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        closed = true
        let pending = handlers
        handlers.removeAll()
        let transport = self.transport
        let session = self.session
        let onClose = self.onClose
        pings?.cancel()
        pings = nil
        lock.unlock()
        transport?.close()
        session?.invalidateAndCancel()
        for handler in pending.values { handler(.exit(.failure(failure))) }
        if notify { onClose?(failure) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(.notRunning, notify: true)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        finish(status == 401 ? .signedOut : .notRunning, notify: true)
    }
}
