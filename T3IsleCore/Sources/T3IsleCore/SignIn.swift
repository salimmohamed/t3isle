import Foundation

public protocol CommandRunner: Sendable {
    func run(_ tool: URL, _ arguments: [String]) async throws -> Data
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    public func run(_ tool: URL, _ arguments: [String]) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw T3Failure.cliMissing }
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
            if process.isRunning { process.terminate() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 && process.terminationReason == .exit {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: T3Failure.cliFailed(process.terminationReason == .uncaughtSignal
                        ? "T3's command-line tool didn't answer." : "T3's command-line tool failed."))
                }
            }
        }
    }
}

public actor T3SignIn {
    static let scopes = ["orchestration:read", "orchestration:operate"]

    private let home: T3Home
    private let store: TokenStore
    private let runner: CommandRunner
    private let label: String
    private var cached: StoredToken?
    private var issuing: Task<StoredToken, Error>?

    public init(home: T3Home, store: TokenStore = FileTokenStore(), runner: CommandRunner = ProcessRunner(),
                label: String = StateFolders.appName()) {
        self.home = home
        self.store = store
        self.runner = runner
        self.label = label
    }

    public func token() async throws -> String {
        if let cached, cached.isUsable() { return cached.token }
        if let saved = store.load(), saved.isUsable() {
            cached = saved
            return saved.token
        }
        return try await issue().token
    }

    public func invalidate() {
        cached = nil
        store.clear()
    }

    private func issue() async throws -> StoredToken {
        if let issuing { return try await issuing.value }
        let task = Task { () throws -> StoredToken in
            var arguments = ["auth", "session", "issue", "--ttl", "30d", "--label", label, "--json"]
            for scope in Self.scopes { arguments += ["--scope", scope] }
            let data = try await runner.run(home.cliTool, arguments)
            return try Self.parseIssued(data)
        }
        issuing = task
        defer { issuing = nil }
        let fresh = try await task.value
        try store.save(fresh)
        cached = fresh
        return fresh
    }

    static func parseIssued(_ data: Data) throws -> StoredToken {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = object["token"] as? String, !token.isEmpty
        else { throw T3Failure.signInRefused("T3's command-line tool didn't issue a session.") }
        let expires = WireDate.parse(object["expiresAt"] as? String) ?? Date().addingTimeInterval(86_400)
        return StoredToken(token: token, expiresAt: expires, sessionId: object["sessionId"] as? String)
    }
}
