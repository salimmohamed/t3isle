import Foundation

public enum ShellUpdate: Sendable {
    case snapshot(ShellSnapshot)
    case threadUpdated(ThreadShell, archived: Bool)
    case threadRemoved(String)
    case projectUpdated(ProjectShell)
    case projectRemoved(String)
    case resyncNeeded
    case disconnected(T3Failure)
}

public actor T3ServerClient {
    private static let protocolHeader = "x-t3-orchestration-protocol"
    private static let protocolVersion = "2"

    private let home: T3Home
    private let signIn: T3SignIn
    private let urlSession: URLSession
    private var socket: RpcSocket?
    private var connecting: Task<RpcSocket, Error>?
    private var shellListeners: [UUID: AsyncStream<ShellUpdate>.Continuation] = [:]
    private var environmentId: String?

    public init(home: T3Home, signIn: T3SignIn) {
        self.home = home
        self.signIn = signIn
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: configuration)
    }

    public func shell() async throws -> ShellSnapshot {
        let data = try await get("api/orchestration/shell", query: [
            URLQueryItem(name: "omitIdleSubagents", value: "1"),
            URLQueryItem(name: "omitOlderSettled", value: "1"),
        ])
        return try Self.decode(ShellSnapshot.self, data)
    }

    public func detail(threadId: String) async throws -> ThreadProjection {
        let data = try await get("api/orchestration/threads/\(Self.pathComponent(threadId))/bounded")
        return try Self.decode(ThreadDetailEnvelope.self, data).projection
    }

    public func environment() async -> String? {
        if let environmentId { return environmentId }
        var request = URLRequest(url: home.serverOrigin().appendingPathComponent(".well-known/t3/environment"))
        request.timeoutInterval = 5
        if let (data, response) = try? await urlSession.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let id = object["environmentId"] as? String {
            environmentId = id
            return id
        }
        environmentId = home.environmentId()
        return environmentId
    }

    @discardableResult
    public func dispatch(_ command: T3Command) async throws -> Int? {
        let payload = try Self.jsonObject(command.payload(commandId: UUID().uuidString.lowercased()))
        do {
            let value = try await connectedSocket().call("orchestration.dispatchCommand", payload: payload)
            return (value as? [String: Any])?["sequence"] as? Int
        } catch T3Failure.signedOut {
            await signIn.invalidate()
            let value = try await connectedSocket().call("orchestration.dispatchCommand", payload: payload)
            return (value as? [String: Any])?["sequence"] as? Int
        }
    }

    public func shellUpdates() -> AsyncStream<ShellUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream(bufferingPolicy: .bufferingNewest(256))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        shellListeners[id] = continuation
        Task { await self.subscribeShell() }
        return stream
    }

    public func disconnect() {
        socket?.close()
        socket = nil
    }

    public func signOut() async {
        disconnect()
        await signIn.signOut()
    }

    private func removeListener(_ id: UUID) {
        shellListeners[id] = nil
        if shellListeners.isEmpty { disconnect() }
    }

    private func broadcast(_ update: ShellUpdate) {
        for listener in shellListeners.values { listener.yield(update) }
    }

    private func subscribeShell() async {
        do {
            let socket = try await connectedSocket()
            socket.request("orchestration.subscribeShell",
                           payload: ["omitIdleSubagents": true, "omitOlderSettled": true]) { [weak self] event in
                guard let self else { return }
                switch event {
                case .chunk(let values):
                    let updates = values.compactMap(Self.shellUpdate)
                    Task { for update in updates { await self.broadcast(update) } }
                case .exit(let result):
                    if case .failure(let failure) = result {
                        Task { await self.broadcast(.disconnected(failure)) }
                    } else {
                        Task { await self.broadcast(.disconnected(.notRunning)) }
                    }
                }
            }
        } catch {
            broadcast(.disconnected(error as? T3Failure ?? .notRunning))
        }
    }

    private func connectedSocket() async throws -> RpcSocket {
        if let socket { return socket }
        if let connecting { return try await connecting.value }
        let signIn = signIn
        let home = home
        let task = Task { [weak self] () throws -> RpcSocket in
            let token = try await signIn.token()
            var components = URLComponents(url: home.serverOrigin().appendingPathComponent("ws"),
                                           resolvingAgainstBaseURL: false)
            components?.scheme = home.serverOrigin().scheme == "https" ? "wss" : "ws"
            components?.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: Self.protocolVersion)]
            guard let url = components?.url else { throw T3Failure.notRunning }
            let socket = RpcSocket()
            socket.connect(url: url, token: token) { [weak self] failure in
                Task { await self?.socketClosed(socket, failure) }
            }
            return socket
        }
        connecting = task
        defer { connecting = nil }
        let socket = try await task.value
        self.socket = socket
        return socket
    }

    private func socketClosed(_ closed: RpcSocket, _ failure: T3Failure) async {
        guard socket === closed else { return }
        socket = nil
        if failure == .signedOut { await signIn.invalidate() }
    }

    private func get(_ path: String, query: [URLQueryItem] = [], retried: Bool = false) async throws -> Data {
        var components = URLComponents(url: home.serverOrigin(), resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "/" + path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw T3Failure.notRunning }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await signIn.token())", forHTTPHeaderField: "Authorization")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: Self.protocolHeader)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw T3Failure.notRunning
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401 where !retried:
            await signIn.invalidate()
            return try await get(path, query: query, retried: true)
        case 401:
            throw T3Failure.signedOut
        default:
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
            throw T3Failure.http(status, message)
        }
    }

    static func pathComponent(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try WireDecoder.make().decode(type, from: data)
        } catch {
            throw T3Failure.unreadable
        }
    }

    static func jsonObject(_ payload: [String: AnyWireValue]) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func shellUpdate(_ value: Any) -> ShellUpdate? {
        guard let object = value as? [String: Any], let kind = object["kind"] as? String,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        let decoder = WireDecoder.make()
        switch kind {
        case "snapshot":
            struct Envelope: Decodable { let snapshot: ShellSnapshot }
            return (try? decoder.decode(Envelope.self, from: data)).map { .snapshot($0.snapshot) }
        case "thread.updated":
            struct Envelope: Decodable { let thread: ThreadShell; let location: String? }
            return (try? decoder.decode(Envelope.self, from: data)).map {
                .threadUpdated($0.thread, archived: $0.location == "archive")
            }
        case "thread.removed":
            return (object["threadId"] as? String).map { .threadRemoved($0) }
        case "project.updated":
            struct Envelope: Decodable { let project: ProjectShell }
            return (try? decoder.decode(Envelope.self, from: data)).map { .projectUpdated($0.project) }
        case "project.removed":
            return (object["projectId"] as? String).map { .projectRemoved($0) }
        case "snapshot-required":
            return .resyncNeeded
        default:
            return nil
        }
    }
}
