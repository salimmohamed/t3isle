import Foundation

public enum PromptKind: Equatable, Sendable {
    case approval(choices: [ApprovalChoice])
    case question(UserInputQuestion, index: Int, count: Int)
}

public struct PendingPrompt: Identifiable, Equatable, Sendable {
    public let threadId: String
    public let threadTitle: String
    public let project: String
    public let providerId: String
    public let requestId: String
    public let requestKind: String
    public let title: String
    public let detail: String?
    public let kind: PromptKind
    public let createdAt: Date?

    public init(threadId: String, threadTitle: String, project: String, providerId: String, requestId: String,
                requestKind: String, title: String, detail: String?, kind: PromptKind, createdAt: Date?) {
        self.threadId = threadId
        self.threadTitle = threadTitle
        self.project = project
        self.providerId = providerId
        self.requestId = requestId
        self.requestKind = requestKind
        self.title = title
        self.detail = detail
        self.kind = kind
        self.createdAt = createdAt
    }

    public var id: String {
        if case .question(let question, _, _) = kind { return "\(requestId)#\(question.id)" }
        return requestId
    }

    public var isApproval: Bool {
        if case .approval = kind { return true }
        return false
    }
}

public struct ActivityEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case command, edit, tool, search, agent, thinking, message }

    public let id: String
    public let kind: Kind
    public let text: String
    public let inProgress: Bool
    public let failed: Bool
    public let at: Date?

    public init(id: String, kind: Kind, text: String, inProgress: Bool, failed: Bool = false, at: Date? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.inProgress = inProgress
        self.failed = failed
        self.at = at
    }
}

public struct PlanProgress: Equatable, Sendable {
    public let planId: String
    public let steps: [PlanStep]
    public let explanation: String?

    public init(planId: String, steps: [PlanStep], explanation: String? = nil) {
        self.planId = planId
        self.steps = steps
        self.explanation = explanation
    }

    public var completed: Int { steps.filter { $0.status == "completed" }.count }
    public var isComplete: Bool { !steps.isEmpty && completed == steps.count }
    public var current: PlanStep? { steps.first { $0.status == "running" } ?? steps.first { $0.status == "pending" } }
}

public struct AgentDetail: Equatable, Sendable {
    public let threadId: String
    public let providerId: String
    public let model: String?
    public let branch: String?
    public let runStatus: String?
    public let runStartedAt: Date?
    public let runCompletedAt: Date?
    public let plan: PlanProgress?
    public let activity: [ActivityEntry]
    public let latestLine: String?

    public init(threadId: String, providerId: String, model: String?, branch: String?, runStatus: String?,
                runStartedAt: Date?, runCompletedAt: Date?, plan: PlanProgress?, activity: [ActivityEntry],
                latestLine: String?) {
        self.threadId = threadId
        self.providerId = providerId
        self.model = model
        self.branch = branch
        self.runStatus = runStatus
        self.runStartedAt = runStartedAt
        self.runCompletedAt = runCompletedAt
        self.plan = plan
        self.activity = activity
        self.latestLine = latestLine
    }

    public var isRunning: Bool {
        guard let runStatus else { return false }
        return InboxBuilder.workingStatuses.contains(runStatus) || runStatus == "waiting"
    }
}

public enum DetailBuilder {
    public static let activityLimit = 6
    static let activityTypes: Set<String> = ["command_execution", "file_change", "dynamic_tool", "web_search",
                                             "file_search", "subagent"]

    public static func detail(_ projection: ThreadProjection) -> AgentDetail {
        let run = latestRun(projection)
        let session = projection.providerSessions.last
        let providerId = run?.providerInstanceId ?? projection.thread.providerInstanceId
            ?? projection.thread.modelSelection?.instanceId ?? session?.providerInstanceId ?? ""
        let runItems = projection.turnItems.filter { run == nil || $0.runId == run?.id }
            .sorted { ($0.ordinal ?? 0) < ($1.ordinal ?? 0) }
        return AgentDetail(
            threadId: projection.thread.id,
            providerId: providerId,
            model: run?.modelSelection?.model ?? session?.model ?? projection.thread.modelSelection?.model,
            branch: projection.thread.branch,
            runStatus: run?.status,
            runStartedAt: run?.displayStart,
            runCompletedAt: run?.completedAt,
            plan: plan(projection, runId: run?.id),
            activity: activity(runItems),
            latestLine: latestLine(runItems)
        )
    }

    static func latestRun(_ projection: ThreadProjection) -> Run? {
        projection.runs.max { ($0.ordinal ?? 0) < ($1.ordinal ?? 0) }
    }

    static func plan(_ projection: ThreadProjection, runId: String?) -> PlanProgress? {
        let todos = projection.plans.filter { $0.kind == "todo_list" && $0.status != "superseded" && !($0.steps ?? []).isEmpty }
        let chosen = todos.last { $0.runId == runId } ?? todos.last
        guard let chosen, let steps = chosen.steps else { return nil }
        return PlanProgress(planId: chosen.id, steps: steps, explanation: chosen.explanation)
    }

    static func activity(_ items: [TurnItem]) -> [ActivityEntry] {
        Array(items.filter { activityTypes.contains($0.type) }.compactMap(entry).suffix(activityLimit))
    }

    static func entry(_ item: TurnItem) -> ActivityEntry? {
        let failed = item.status == "failed"
        let make = { (kind: ActivityEntry.Kind, text: String?) -> ActivityEntry? in
            guard let text, !text.isEmpty else { return nil }
            return ActivityEntry(id: item.id, kind: kind, text: text, inProgress: item.isInProgress, failed: failed,
                                 at: item.updatedAt ?? item.startedAt)
        }
        switch item.type {
        case "command_execution":
            let command = item.input?.stringValue.map(InboxBuilder.firstLine)
            return make(.command, command.flatMap { LineText.plain($0, command: true) }.map { "$ \($0)" })
        case "file_change":
            let path = item.fileName ?? item.changes?.compactMap(\.path).first
            return make(.edit, path.map { "Edited \(URL(fileURLWithPath: $0).lastPathComponent)" })
        case "dynamic_tool":
            return make(.tool, item.title ?? item.toolName.map(toolLabel))
        case "web_search":
            return make(.search, item.title.map { "Searching “\($0)”" } ?? "Searching the web")
        case "file_search":
            return make(.search, item.title ?? "Searching files")
        case "subagent":
            return make(.agent, item.title.map { "Agent: \($0)" })
        default:
            return nil
        }
    }

    static func toolLabel(_ name: String) -> String {
        let short = name.split(separator: "__").last.map(String.init) ?? name
        return short.replacingOccurrences(of: "_", with: " ")
    }

    static func latestLine(_ items: [TurnItem]) -> String? {
        for item in items.reversed() {
            switch item.type {
            case "reasoning" where item.isInProgress:
                return "Thinking…"
            case "assistant_message":
                if let text = item.text, let line = item.isInProgress ? LineText.lastMeaningful(text) : LineText.firstMeaningful(text) {
                    return line
                }
            default:
                if activityTypes.contains(item.type), let entry = entry(item) { return entry.text }
            }
        }
        return nil
    }

    public static func prompts(_ projection: ThreadProjection, title: String, project: String) -> [PendingPrompt] {
        let pending = projection.runtimeRequests.filter {
            $0.status == "pending" && !InboxBuilder.ignoredRequestKinds.contains($0.kind)
                && $0.responseCapability?.type != "not_resumable"
        }
        let providerId = projection.thread.providerInstanceId ?? projection.thread.modelSelection?.instanceId ?? ""
        return pending.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }.flatMap { request -> [PendingPrompt] in
            let item = projection.turnItems.last { $0.requestId == request.id }
            if request.kind == "user_input" {
                let questions = item?.questions ?? []
                return questions.enumerated().map { index, question in
                    PendingPrompt(threadId: projection.thread.id, threadTitle: title, project: project,
                                  providerId: providerId, requestId: request.id, requestKind: request.kind,
                                  title: question.header ?? "Question", detail: question.question,
                                  kind: .question(question, index: index, count: questions.count),
                                  createdAt: request.createdAt)
                }
            }
            let choices = item?.options?.isEmpty == false ? item?.options ?? [] : defaultChoices
            return [PendingPrompt(threadId: projection.thread.id, threadTitle: title, project: project,
                                  providerId: providerId, requestId: request.id, requestKind: request.kind,
                                  title: approvalTitle(request.kind), detail: item?.prompt ?? item?.reason ?? item?.title,
                                  kind: .approval(choices: choices), createdAt: request.createdAt)]
        }
    }

    public static let defaultChoices = [
        ApprovalChoice(decision: ApprovalDecision.accept.rawValue, label: "Approve"),
        ApprovalChoice(decision: ApprovalDecision.decline.rawValue, label: "Deny"),
    ]

    static func approvalTitle(_ kind: String) -> String {
        switch kind {
        case "command": "Run a command?"
        case "file-change": "Edit files?"
        case "file-read": "Read files?"
        case "permission": "Allow access?"
        case "mcp-elicitation": "Tool needs input"
        default: "Approval needed"
        }
    }
}
