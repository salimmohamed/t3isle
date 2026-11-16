import Foundation

public struct ShellSnapshot: Decodable, Sendable {
    public var snapshotSequence: Int
    public var threads: [ThreadShell]
    public var projects: [ProjectShell]

    public init(snapshotSequence: Int = 0, threads: [ThreadShell], projects: [ProjectShell]) {
        self.snapshotSequence = snapshotSequence
        self.threads = threads
        self.projects = projects
    }
}

public struct ProjectShell: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var workspaceRoot: String?

    public init(id: String, title: String, workspaceRoot: String? = nil) {
        self.id = id
        self.title = title
        self.workspaceRoot = workspaceRoot
    }
}

public struct ModelSelection: Codable, Equatable, Sendable {
    public var instanceId: String?
    public var model: String?

    public init(instanceId: String? = nil, model: String? = nil) {
        self.instanceId = instanceId
        self.model = model
    }
}

public struct PendingRequestSummary: Decodable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var createdAt: Date?

    public init(id: String, kind: String, createdAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}

public struct VisibleMessage: Decodable, Equatable, Sendable {
    public var role: String?
    public var text: String?

    public init(role: String? = nil, text: String? = nil) {
        self.role = role
        self.text = text
    }
}

public struct Lineage: Decodable, Equatable, Sendable {
    public var parentThreadId: String?
    public var relationshipToParent: String?
    public var sideChat: Bool?

    public init(parentThreadId: String? = nil, relationshipToParent: String? = nil, sideChat: Bool? = nil) {
        self.parentThreadId = parentThreadId
        self.relationshipToParent = relationshipToParent
        self.sideChat = sideChat
    }
}

public struct DelegatedFrom: Decodable, Equatable, Sendable {
    public var environmentId: String?
    public var threadId: String?
    public var title: String?

    public init(environmentId: String? = nil, threadId: String? = nil, title: String? = nil) {
        self.environmentId = environmentId
        self.threadId = threadId
        self.title = title
    }
}

public struct PullRequestRef: Decodable, Equatable, Sendable {
    public var number: Int?
    public var watch: AnyWireValue?
}

public struct ThreadShell: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var projectId: String?
    public var title: String
    public var providerInstanceId: String?
    public var modelSelection: ModelSelection?
    public var branch: String?
    public var lineage: Lineage?
    public var delegatedFrom: DelegatedFrom?
    public var status: String
    public var activityRunStatus: String?
    public var latestRunId: String?
    public var activeRunId: String?
    public var latestRunRequestedAt: Date?
    public var latestRunStartedAt: Date?
    public var latestRunCompletedAt: Date?
    public var activityRunStartedAt: Date?
    public var blockedOnThreadWait: Bool?
    public var lastError: String?
    public var pendingRuntimeRequest: PendingRequestSummary?
    public var pendingGuestMessageCount: Int?
    public var pendingBackgroundTasks: [AnyWireValue]?
    public var pullRequests: [PullRequestRef]?
    public var latestVisibleMessage: VisibleMessage?
    public var hasActionableProposedPlan: Bool?
    public var updatedAt: Date?
    public var archivedAt: Date?
    public var deletedAt: Date?
    public var settledOverride: String?
    public var settledAt: Date?
    public var snoozedUntil: Date?
    public var snoozedAt: Date?
    public var lastVisitedAt: Date?

    public init(id: String, projectId: String? = nil, title: String, providerInstanceId: String? = nil,
                modelSelection: ModelSelection? = nil, branch: String? = nil, lineage: Lineage? = nil,
                delegatedFrom: DelegatedFrom? = nil, status: String = "idle", activityRunStatus: String? = nil, latestRunId: String? = nil,
                activeRunId: String? = nil, latestRunRequestedAt: Date? = nil, latestRunStartedAt: Date? = nil,
                latestRunCompletedAt: Date? = nil, activityRunStartedAt: Date? = nil,
                blockedOnThreadWait: Bool? = nil, lastError: String? = nil,
                pendingRuntimeRequest: PendingRequestSummary? = nil, pendingGuestMessageCount: Int? = nil,
                pendingBackgroundTasks: [AnyWireValue]? = nil, pullRequests: [PullRequestRef]? = nil,
                latestVisibleMessage: VisibleMessage? = nil, hasActionableProposedPlan: Bool? = nil,
                updatedAt: Date? = nil, archivedAt: Date? = nil, deletedAt: Date? = nil,
                settledOverride: String? = nil, settledAt: Date? = nil, snoozedUntil: Date? = nil,
                snoozedAt: Date? = nil, lastVisitedAt: Date? = nil) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.providerInstanceId = providerInstanceId
        self.modelSelection = modelSelection
        self.branch = branch
        self.lineage = lineage
        self.delegatedFrom = delegatedFrom
        self.status = status
        self.activityRunStatus = activityRunStatus
        self.latestRunId = latestRunId
        self.activeRunId = activeRunId
        self.latestRunRequestedAt = latestRunRequestedAt
        self.latestRunStartedAt = latestRunStartedAt
        self.latestRunCompletedAt = latestRunCompletedAt
        self.activityRunStartedAt = activityRunStartedAt
        self.blockedOnThreadWait = blockedOnThreadWait
        self.lastError = lastError
        self.pendingRuntimeRequest = pendingRuntimeRequest
        self.pendingGuestMessageCount = pendingGuestMessageCount
        self.pendingBackgroundTasks = pendingBackgroundTasks
        self.pullRequests = pullRequests
        self.latestVisibleMessage = latestVisibleMessage
        self.hasActionableProposedPlan = hasActionableProposedPlan
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.settledOverride = settledOverride
        self.settledAt = settledAt
        self.snoozedUntil = snoozedUntil
        self.snoozedAt = snoozedAt
        self.lastVisitedAt = lastVisitedAt
    }

    public var isSubagent: Bool {
        lineage?.relationshipToParent == "subagent" || delegatedFrom != nil
    }

    public var isSideChat: Bool {
        lineage?.sideChat == true
    }
}

public struct ThreadProjection: Decodable, Sendable {
    public var thread: ProjectedThread
    public var runs: [Run]
    public var plans: [Plan]
    public var runtimeRequests: [RuntimeRequest]
    public var turnItems: [TurnItem]
    public var providerSessions: [ProviderSession]

    public init(thread: ProjectedThread, runs: [Run] = [], plans: [Plan] = [], runtimeRequests: [RuntimeRequest] = [],
                turnItems: [TurnItem] = [], providerSessions: [ProviderSession] = []) {
        self.thread = thread
        self.runs = runs
        self.plans = plans
        self.runtimeRequests = runtimeRequests
        self.turnItems = turnItems
        self.providerSessions = providerSessions
    }
}

public struct ThreadDetailEnvelope: Decodable, Sendable {
    public var snapshotSequence: Int?
    public var projection: ThreadProjection
}

public struct ProjectedThread: Decodable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var providerInstanceId: String?
    public var modelSelection: ModelSelection?
    public var branch: String?

    public init(id: String, title: String? = nil, providerInstanceId: String? = nil,
                modelSelection: ModelSelection? = nil, branch: String? = nil) {
        self.id = id
        self.title = title
        self.providerInstanceId = providerInstanceId
        self.modelSelection = modelSelection
        self.branch = branch
    }
}

public struct Run: Decodable, Equatable, Sendable {
    public var id: String
    public var ordinal: Int?
    public var status: String
    public var requestedAt: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var workStartedAt: Date?
    public var modelSelection: ModelSelection?
    public var providerInstanceId: String?

    public init(id: String, ordinal: Int? = nil, status: String, requestedAt: Date? = nil, startedAt: Date? = nil,
                completedAt: Date? = nil, workStartedAt: Date? = nil, modelSelection: ModelSelection? = nil,
                providerInstanceId: String? = nil) {
        self.id = id
        self.ordinal = ordinal
        self.status = status
        self.requestedAt = requestedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.workStartedAt = workStartedAt
        self.modelSelection = modelSelection
        self.providerInstanceId = providerInstanceId
    }

    public var displayStart: Date? { workStartedAt ?? startedAt ?? requestedAt }
}

public struct PlanStep: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var status: String

    public init(id: String, text: String, status: String) {
        self.id = id
        self.text = text
        self.status = status
    }
}

public struct Plan: Decodable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var runId: String?
    public var status: String?
    public var steps: [PlanStep]?
    public var explanation: String?

    public init(id: String, kind: String = "todo_list", runId: String? = nil, status: String? = nil,
                steps: [PlanStep]? = nil, explanation: String? = nil) {
        self.id = id
        self.kind = kind
        self.runId = runId
        self.status = status
        self.steps = steps
        self.explanation = explanation
    }
}

public struct RuntimeRequest: Decodable, Equatable, Sendable {
    public struct Capability: Decodable, Equatable, Sendable {
        public var type: String
        public var supportsFeedback: Bool?

        public init(type: String, supportsFeedback: Bool? = nil) {
            self.type = type
            self.supportsFeedback = supportsFeedback
        }
    }

    public var id: String
    public var kind: String
    public var status: String
    public var createdAt: Date?
    public var responseCapability: Capability?

    public init(id: String, kind: String, status: String, createdAt: Date? = nil, responseCapability: Capability? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.responseCapability = responseCapability
    }
}

public struct ProviderSession: Decodable, Equatable, Sendable {
    public var driver: String?
    public var providerInstanceId: String?
    public var status: String?
    public var model: String?
}

public struct QuestionOption: Decodable, Equatable, Sendable, Hashable {
    public var label: String
    public var description: String?
    public var value: String?

    public init(label: String, description: String? = nil, value: String? = nil) {
        self.label = label
        self.description = description
        self.value = value
    }

    public var answerValue: String { value ?? label }
}

public struct UserInputQuestion: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var header: String?
    public var question: String
    public var options: [QuestionOption]
    public var multiSelect: Bool?
    public var allowCustomAnswer: Bool?
    public var required: Bool?

    public init(id: String, header: String? = nil, question: String, options: [QuestionOption] = [],
                multiSelect: Bool? = nil, allowCustomAnswer: Bool? = nil, required: Bool? = nil) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
        self.allowCustomAnswer = allowCustomAnswer
        self.required = required
    }

    public var allowsFreeText: Bool { allowCustomAnswer != false }
}

public struct ApprovalChoice: Decodable, Equatable, Sendable, Hashable {
    public var decision: String
    public var label: String

    public init(decision: String, label: String) {
        self.decision = decision
        self.label = label
    }
}

public struct FileChangeEntry: Decodable, Equatable, Sendable {
    public var path: String?
}

public struct TurnItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var runId: String?
    public var ordinal: Int?
    public var status: String?
    public var title: String?
    public var startedAt: Date?
    public var updatedAt: Date?
    public var input: AnyWireValue?
    public var text: String?
    public var fileName: String?
    public var changes: [FileChangeEntry]?
    public var toolName: String?
    public var requestId: String?
    public var requestKind: String?
    public var prompt: String?
    public var reason: String?
    public var options: [ApprovalChoice]?
    public var questions: [UserInputQuestion]?

    public init(id: String, type: String, runId: String? = nil, ordinal: Int? = nil, status: String? = nil,
                title: String? = nil, startedAt: Date? = nil, updatedAt: Date? = nil, input: AnyWireValue? = nil,
                text: String? = nil, fileName: String? = nil, changes: [FileChangeEntry]? = nil,
                toolName: String? = nil, requestId: String? = nil, requestKind: String? = nil,
                prompt: String? = nil, reason: String? = nil, options: [ApprovalChoice]? = nil,
                questions: [UserInputQuestion]? = nil) {
        self.id = id
        self.type = type
        self.runId = runId
        self.ordinal = ordinal
        self.status = status
        self.title = title
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.input = input
        self.text = text
        self.fileName = fileName
        self.changes = changes
        self.toolName = toolName
        self.requestId = requestId
        self.requestKind = requestKind
        self.prompt = prompt
        self.reason = reason
        self.options = options
        self.questions = questions
    }

    public var isInProgress: Bool {
        ["pending", "running", "waiting"].contains(status ?? "")
    }
}

public indirect enum AnyWireValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AnyWireValue])
    case object([String: AnyWireValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyWireValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: AnyWireValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> AnyWireValue? {
        if case .object(let value) = self { return value[key] }
        return nil
    }

    public var isNull: Bool { self == .null }
}

public enum WireDecoder {
    public static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = WireDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(string)")
            }
            return date
        }
        return decoder
    }
}
