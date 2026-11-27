import Foundation

public enum ShellUpdate: Sendable {
    case snapshot(ShellSnapshot)
    case threadUpdated(ThreadShell, archived: Bool)
    case threadRemoved(String)
    case projectUpdated(ProjectShell)
    case projectRemoved(String)
    case disconnected(T3Failure)
}

public actor T3ServerClient {
    private static let protocolHeader = "x-t3-orchestration-protocol"
    private static let protocolVersion = "2"
    private static let mcpProtocolVersion = "2025-06-18"

    private let home: T3Home
    private let signIn: T3SignIn
    private let linkSignIn: T3SignIn?
    private let urlSession: URLSession
    private let clock: any T3Clock
    private var socket: RpcSocket?
    private var connecting: Task<RpcSocket, Error>?
    private var environmentId: String?
    private var mcpSession: String?
    private var mcpRequestId = 0
    private var linkBackoff = SessionBackoff()

    public init(home: T3Home, signIn: T3SignIn, linkSignIn: T3SignIn? = nil, clock: any T3Clock = LiveClock()) {
        self.home = home
        self.signIn = signIn
        self.linkSignIn = linkSignIn
        self.clock = clock
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        urlSession = URLSession(configuration: configuration)
    }

    public func detail(threadId: String) async throws -> ThreadProjection {
        let data = try await get("api/orchestration/threads/\(Self.pathComponent(threadId))/bounded")
        return try Self.decode(ThreadDetailEnvelope.self, data).projection
    }

    public func detail(threadId: String, in environment: String?) async throws -> ThreadProjection {
        guard let environment else { return try await detail(threadId: threadId) }
        let values = try await connectedSocket().firstChunk("peerLinks.subscribeThread",
                                                            payload: ["environmentId": environment, "threadId": threadId])
        return try Self.relaySnapshot(values)
    }

    static func relaySnapshot(_ values: [Any]) throws -> ThreadProjection {
        guard let snapshot = values.first(where: { ($0 as? [String: Any])?["kind"] as? String == "snapshot" }),
              let data = try? JSONSerialization.data(withJSONObject: snapshot)
        else { throw T3Failure.unreadable }
        return try decode(ThreadDetailEnvelope.self, data).projection
    }

    public func dispatch(_ command: T3Command, in environment: String?) async throws {
        guard let environment else {
            try await dispatch(command)
            return
        }
        let tool = try LinkedCommand.tool(for: command, in: environment)
        _ = try McpReply.structuredContent(try await mcp(tool.name, tool.arguments, waitsOutBackoff: false))
    }

    public func linkedRead() async -> LinkedRead? {
        guard let list = try? await callTool("t3_environment_links", [:], as: LinkedEnvironmentList.self) else {
            return nil
        }
        return await withTaskGroup(of: (String, ShellSnapshot?).self) { group in
            for environment in list.reachable {
                group.addTask { (environment.id, try? await self.linkedSnapshot(of: environment)) }
            }
            var read = LinkedRead(reachable: Set(list.reachable.map(\.id)))
            for await (environment, part) in group {
                guard let part else { continue }
                read.answered.insert(environment)
                read.threads += part.threads
                read.projects += part.projects
            }
            return read
        }
    }

    private func linkedSnapshot(of environment: LinkedEnvironment) async throws -> ShellSnapshot {
        var threads: [ThreadShell] = []
        var cursor: Int? = 0
        while let current = cursor {
            let page = try await callTool("t3_thread_list", [
                "environmentId": environment.id, "allProjects": true, "settled": false,
                "includeSubagents": true, "limit": 100, "cursor": current,
            ], as: LinkedThreadPage.self)
            threads += page.threads.map { $0.shell(in: environment) }
            cursor = page.nextCursor.flatMap { $0 > current ? $0 : nil }
        }
        let projects = try? await callTool("t3_project_list", ["environmentId": environment.id, "limit": 100],
                                           as: LinkedProjectPage.self).projects
        return ShellSnapshot(threads: threads, projects: projects ?? [])
    }

    private func callTool<T: Decodable>(_ name: String, _ arguments: [String: Any], as type: T.Type) async throws -> T {
        try Self.decode(type, try McpReply.structuredContent(try await mcp(name, arguments)))
    }

    private func mcp(_ name: String, _ arguments: [String: Any], waitsOutBackoff: Bool = true) async throws -> Data {
        guard !waitsOutBackoff || linkBackoff.allows(at: clock.now) else { throw T3Failure.signedOut }
        do {
            let data = try await mcpCall(name, arguments)
            linkBackoff.accepted()
            return data
        } catch T3Failure.signedOut {
            linkBackoff.rejected(at: clock.now)
            throw T3Failure.signedOut
        }
    }

    private func mcpCall(_ name: String, _ arguments: [String: Any], retried: Bool = false) async throws -> Data {
        guard let linkSignIn else { throw T3Failure.notRunning }
        let session = try await mcpSessionId()
        mcpRequestId += 1
        let (data, status) = try await postMcp(McpReply.toolCall(id: mcpRequestId, name: name, arguments: arguments),
                                               session: session)
        switch status {
        case 200..<300:
            return data
        case 401 where !retried:
            mcpSession = nil
            await linkSignIn.invalidate()
            return try await mcpCall(name, arguments, retried: true)
        case 400 where !retried, 404 where !retried:
            mcpSession = nil
            return try await mcpCall(name, arguments, retried: true)
        case 401:
            throw T3Failure.signedOut
        default:
            throw T3Failure.http(status, nil)
        }
    }

    private func mcpSessionId() async throws -> String {
        if let mcpSession { return mcpSession }
        let initialize = McpReply.request(id: 0, method: "initialize", params: [
            "protocolVersion": Self.mcpProtocolVersion, "capabilities": [String: Any](),
            "clientInfo": ["name": "t3isle", "version": "1"],
        ])
        let (data, status, session) = try await postMcpReturningSession(initialize, session: nil)
        guard (200..<300).contains(status), let session else {
            if status == 401 { await linkSignIn?.invalidate() }
            throw status == 401 ? T3Failure.signedOut : T3Failure.http(status, String(data: data, encoding: .utf8))
        }
        let initialized = (try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])) ?? Data()
        _ = try? await postMcp(initialized, session: session)
        mcpSession = session
        return session
    }

    private func postMcp(_ body: Data, session: String) async throws -> (Data, Int) {
        let (data, status, _) = try await postMcpReturningSession(body, session: session)
        return (data, status)
    }

    private func postMcpReturningSession(_ body: Data, session: String?) async throws -> (Data, Int, String?) {
        guard let linkSignIn, let origin = home.serverOrigin() else { throw T3Failure.notRunning }
        var request = URLRequest(url: origin.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(try await linkSignIn.token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.mcpProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let session { request.setValue(session, forHTTPHeaderField: "MCP-Session-Id") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw T3Failure.notRunning
        }
        let http = response as? HTTPURLResponse
        let payload = http?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true
            ? McpReply.lastEvent(data) : data
        return (payload, http?.statusCode ?? 0, http?.value(forHTTPHeaderField: "MCP-Session-Id"))
    }

    public func environment() async -> String? {
        if let environmentId { return environmentId }
        guard let origin = home.serverOrigin() else { return home.environmentId() }
        var request = URLRequest(url: origin.appendingPathComponent(".well-known/t3/environment"))
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
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.disconnect() }
        }
        Task { await self.subscribeShell(into: continuation) }
        return stream
    }

    public func disconnect() {
        connecting?.cancel()
        connecting = nil
        socket?.close()
        socket = nil
    }

    private func subscribeShell(into continuation: AsyncStream<ShellUpdate>.Continuation) async {
        do {
            let socket = try await connectedSocket()
            socket.request("orchestration.subscribeShell",
                           payload: ["omitIdleSubagents": true, "omitOlderSettled": true]) { event in
                switch event {
                case .chunk(let values):
                    for update in values.flatMap(Self.shellUpdates) { continuation.yield(update) }
                case .exit(let result):
                    if case .failure(let failure) = result {
                        continuation.yield(.disconnected(failure))
                    } else {
                        continuation.yield(.disconnected(.notRunning))
                    }
                    continuation.finish()
                }
            }
        } catch {
            continuation.yield(.disconnected(error as? T3Failure ?? .notRunning))
            continuation.finish()
        }
    }

    private func connectedSocket() async throws -> RpcSocket {
        if let socket, !socket.isClosed { return socket }
        if let connecting { return try await connecting.value }
        let signIn = signIn
        let home = home
        let task = Task { [weak self] () throws -> RpcSocket in
            let token = try await signIn.token()
            guard let origin = home.serverOrigin() else { throw T3Failure.notRunning }
            var components = URLComponents(url: origin.appendingPathComponent("ws"), resolvingAgainstBaseURL: false)
            components?.scheme = origin.scheme == "https" ? "wss" : "ws"
            components?.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: Self.protocolVersion)]
            guard let url = components?.url else { throw T3Failure.notRunning }
            let socket = RpcSocket()
            socket.connect(url: url, token: token) { [weak self] failure in
                Task { await self?.socketClosed(socket, failure) }
            }
            return socket
        }
        connecting = task
        defer { if connecting == task { connecting = nil } }
        let socket = try await task.value
        guard !task.isCancelled else {
            socket.close()
            throw T3Failure.notRunning
        }
        self.socket = socket
        return socket
    }

    private func socketClosed(_ closed: RpcSocket, _ failure: T3Failure) async {
        guard socket === closed else { return }
        socket = nil
        if failure == .signedOut { await signIn.invalidate() }
    }

    private func get(_ path: String, query: [URLQueryItem] = [], retried: Bool = false) async throws -> Data {
        guard let origin = home.serverOrigin() else { throw T3Failure.notRunning }
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
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

    static func shellUpdates(_ value: Any) -> [ShellUpdate] {
        guard let object = value as? [String: Any], object["kind"] as? String == "snapshot",
              object["resolvedRepositoryIdentityRoots"] != nil
        else { return shellUpdate(value).map { [$0] } ?? [] }
        struct Enrichment: Decodable { let snapshot: Projects }
        struct Projects: Decodable { let projects: [ProjectShell] }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let enrichment = try? WireDecoder.make().decode(Enrichment.self, from: data)
        else { return [] }
        return enrichment.snapshot.projects.map { .projectUpdated($0) }
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
        default:
            return nil
        }
    }
}
