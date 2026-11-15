import Foundation

public struct T3Thread: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectId: String?
    public let project: String
    public let providerId: String
    public let provider: String
    public let model: String?
    public let branch: String?
    public let mood: ThreadMood
    public let since: Date?
    public let updatedAt: Date
    public var snoozedUntil: Date?
    public var waitingOn: String?
    public var line: String?
    public let pendingRequestId: String?
    public let runStartedAt: Date?

    public init(id: String, title: String, projectId: String? = nil, project: String, providerId: String = "",
                provider: String, model: String? = nil, branch: String? = nil, mood: ThreadMood, since: Date?,
                updatedAt: Date, snoozedUntil: Date? = nil, waitingOn: String? = nil, line: String? = nil,
                pendingRequestId: String? = nil, runStartedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.projectId = projectId
        self.project = project
        self.providerId = providerId
        self.provider = provider
        self.model = model
        self.branch = branch
        self.mood = mood
        self.since = since
        self.updatedAt = updatedAt
        self.snoozedUntil = snoozedUntil
        self.waitingOn = waitingOn
        self.line = line
        self.pendingRequestId = pendingRequestId
        self.runStartedAt = runStartedAt
    }

    public var status: String {
        mood == .waiting ? "Waiting on \(waitingOn ?? "work")" : mood.label
    }

    public var isSnoozed: Bool { snoozedUntil != nil && !mood.isBusy }
}

public enum InboxSection: String, CaseIterable, Sendable {
    case limits, waiting, working, snoozed
}

public struct InboxBuilder {
    static let workingStatuses: Set<String> = ["queued", "preparing", "starting", "running"]
    static let ignoredRequestKinds: Set<String> = ["auth_refresh", "dynamic_tool_call"]

    public let providerNames: [String: String]

    public init(providerNames: [String: String] = [:]) {
        self.providerNames = providerNames
    }

    public func threads(from shells: [ThreadShell], projects: [String: ProjectShell], now: Date = Date()) -> [T3Thread] {
        let listed = shells.filter { Self.belongsInInbox($0) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        let built = listed.map { thread(from: $0, project: $0.projectId.flatMap { projects[$0] }, now: now) }
        return built.enumerated()
            .sorted { ($0.element.mood, $0.offset) < ($1.element.mood, $1.offset) }
            .map(\.element)
    }

    public static func belongsInInbox(_ shell: ThreadShell) -> Bool {
        guard shell.archivedAt == nil, shell.deletedAt == nil else { return false }
        return shell.settledOverride != "settled" || hasPendingRequest(shell) || workingStatuses.contains(runStatus(shell))
    }

    static func runStatus(_ shell: ThreadShell) -> String {
        shell.activityRunStatus ?? shell.status
    }

    static func hasPendingRequest(_ shell: ThreadShell) -> Bool {
        guard let pending = shell.pendingRuntimeRequest else { return false }
        return !ignoredRequestKinds.contains(pending.kind)
    }

    public static func mood(_ shell: ThreadShell) -> ThreadMood {
        let status = runStatus(shell)
        if hasPendingRequest(shell) || status == "waiting" { return .needsYou }
        if workingStatuses.contains(status) { return .working }
        if status == "failed" { return .failed }
        if waitingOn(shell) != nil { return .waiting }
        if status == "completed",
           (shell.latestRunCompletedAt ?? .distantPast) > (shell.lastVisitedAt ?? .distantPast) {
            return .replied
        }
        return .idle
    }

    static func waitingOn(_ shell: ThreadShell) -> String? {
        let agents = shell.pendingBackgroundTasks?.count ?? 0
        if agents > 0 { return agents == 1 ? "1 agent" : "\(agents) agents" }
        if shell.blockedOnThreadWait == true { return "agents" }
        if let pr = shell.pullRequests?.first(where: { $0.watch != nil && $0.watch?.isNull == false }), let number = pr.number {
            return "PR #\(number)"
        }
        return nil
    }

    public static func isSnoozed(_ shell: ThreadShell, now: Date) -> Bool {
        guard let until = shell.snoozedUntil, until > now else { return false }
        if let pending = shell.pendingRuntimeRequest, !ignoredRequestKinds.contains(pending.kind) {
            guard pending.kind == "user_input" else { return false }
            if let at = shell.snoozedAt, let created = pending.createdAt, created > at { return false }
        }
        if (shell.pendingGuestMessageCount ?? 0) > 0 { return false }
        if runStatus(shell) == "failed" {
            guard let at = shell.snoozedAt else { return false }
            if let completed = shell.latestRunCompletedAt, completed > at { return false }
        }
        return true
    }

    func thread(from shell: ThreadShell, project: ProjectShell?, now: Date) -> T3Thread {
        let mood = Self.mood(shell)
        let providerId = shell.providerInstanceId ?? shell.modelSelection?.instanceId ?? ""
        let runStart = shell.activityRunStartedAt ?? shell.latestRunStartedAt ?? shell.latestRunRequestedAt
        return T3Thread(
            id: shell.id,
            title: shell.title.isEmpty ? "Untitled" : shell.title,
            projectId: shell.projectId,
            project: project?.title ?? "",
            providerId: providerId,
            provider: providerNames[providerId] ?? Self.displayName(provider: providerId),
            model: shell.modelSelection?.model,
            branch: shell.branch,
            mood: mood,
            since: mood == .working || mood == .needsYou ? runStart : shell.latestRunCompletedAt,
            updatedAt: shell.updatedAt ?? .distantPast,
            snoozedUntil: Self.isSnoozed(shell, now: now) ? shell.snoozedUntil : nil,
            waitingOn: mood == .waiting ? Self.waitingOn(shell) : nil,
            line: Self.line(shell, mood: mood),
            pendingRequestId: Self.hasPendingRequest(shell) ? shell.pendingRuntimeRequest?.id : nil,
            runStartedAt: runStart
        )
    }

    static func line(_ shell: ThreadShell, mood: ThreadMood) -> String? {
        if mood == .failed, let error = shell.lastError { return LineText.plain(firstLine(error)) }
        guard let message = shell.latestVisibleMessage, let text = message.text else { return nil }
        let rendered = LineText.firstMeaningful(text)
        return message.role == "user" ? rendered.map { "You: \($0)" } : rendered
    }

    static func firstLine(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).first ?? "")
    }

    public static func displayName(provider id: String) -> String {
        switch id {
        case "claudeAgent", "claude": "Claude"
        case "codex": "Codex"
        case "": "Agent"
        default: id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

public enum LineText {
    public static func firstMeaningful(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let isHeading = { (line: String) -> Bool in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("#") || (trimmed.hasPrefix("**") && trimmed.hasSuffix("**"))
        }
        return lines.filter { !isHeading($0) }.lazy.compactMap { plain($0) }.first
            ?? lines.lazy.compactMap { plain($0) }.first
    }

    public static func lastMeaningful(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).map(String.init).compactMap { plain($0) }.last
    }

    public static func plain(_ line: String, command: Bool = false) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("```") else { return nil }
        if command {
            text = text.replacingOccurrences(of: #"^cd\s+\S+\s*&&\s*"#, with: "", options: .regularExpression)
        } else {
            text = text.replacingOccurrences(of: #"^(#+|>|[-*+]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?:~|/[^\s/]+)(?:/[^\s/]+)*/([^\s/]+)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.isEmpty ? nil : String(text.prefix(200))
    }
}
