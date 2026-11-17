import Foundation

public final class DemoSource: T3Source, @unchecked Sendable {
    private struct Agent {
        var shell: ThreadShell
        var plan: [PlanStep]
        var activity: [TurnItem]
        var requests: [RuntimeRequest] = []
        var requestItems: [TurnItem] = []
        var runStart: Date
    }

    private static let script: [(String, String)] = [
        ("$ swift test --filter CheckoutTests", "command_execution"), ("Sources/Checkout/Cart.swift", "file_change"),
        ("$ npm run lint", "command_execution"), ("Tests/CartTests.swift", "file_change"),
        ("$ git diff --stat", "command_execution"), ("Sources/Queue/JobQueue.swift", "file_change"),
    ]

    private let lock = NSLock()
    private var agents: [String: Agent] = [:]
    private var order: [String] = []
    private let projects = [
        ProjectShell(id: "demo-web", title: "web"), ProjectShell(id: "demo-api", title: "payments-api"),
        ProjectShell(id: "demo-infra", title: "infra"),
    ]
    private var step = 0
    private var continuation: AsyncStream<ShellUpdate>.Continuation?
    private var timer: Task<Void, Never>?
    private var sequence = 0

    public init() {
        let now = Date()
        add(Self.shell("demo-checkout", "Fix flaky checkout test", "demo-web", provider: "claudeAgent",
                       model: "claude-opus-5-5", branch: "fix/checkout-flake", status: "running", start: now.addingTimeInterval(-340)),
            plan: ["Reproduce the flake", "Find the race in Cart", "Wait for the debounce in tests", "Run the suite 20 times"],
            done: 1, start: now.addingTimeInterval(-340))
        add(Self.shell("demo-webhooks", "Refactor billing webhooks", "demo-api", provider: "claudeAgent",
                       model: "claude-sonnet-5-5", branch: "billing-retries", status: "running", start: now.addingTimeInterval(-920)),
            plan: ["Read the webhook handler", "Add a retry policy", "Write tests"], done: 1, start: now.addingTimeInterval(-920))
        add(Self.shell("demo-queues", "Migrate cron jobs to queues", "demo-infra", provider: "codex",
                       model: "gpt-5.5-codex", branch: "queues", status: "running", start: now.addingTimeInterval(-1500)),
            plan: ["List cron jobs", "Create queue workers", "Remove old cron entries"], done: 2, start: now.addingTimeInterval(-1500))
        add(Self.shell("demo-roadmap", "Draft Q3 roadmap notes", "demo-web", provider: "claudeAgent", model: "claude-opus-5-5",
                       status: "completed", completed: now.addingTimeInterval(-600),
                       message: "The draft is in roadmap-q3.md. Want me to tighten the intro?"),
            plan: [], done: 0, start: now.addingTimeInterval(-1800))
        add(Self.shell("demo-postgres", "Upgrade Postgres to 17", "demo-infra", provider: "codex", model: "gpt-5.5-codex",
                       status: "failed", completed: now.addingTimeInterval(-3000), error: "error: no such module 'PostgresNIO'"),
            plan: [], done: 0, start: now.addingTimeInterval(-3600))
        add(Self.shell("demo-flags", "Tidy up feature flags", "demo-web", provider: "claudeAgent", model: "claude-opus-5-5",
                       status: "completed", completed: now.addingTimeInterval(-7200),
                       message: "Removed four stale flags.", snoozedUntil: now.addingTimeInterval(2 * 3600 + 600)),
            plan: [], done: 0, start: now.addingTimeInterval(-9000))
        raiseApproval("demo-webhooks", kind: "command", prompt: "rm -rf .build && swift build", at: now.addingTimeInterval(-20))
        raiseQuestion("demo-webhooks", at: now.addingTimeInterval(-10))
        raiseApproval("demo-checkout", kind: "file-change", prompt: "Edit Tests/CartTests.swift (+12 −3)", at: now.addingTimeInterval(-5))
    }

    public func updates() async -> AsyncStream<ShellUpdate> {
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        lock.lock()
        self.continuation = continuation
        let snapshot = ShellSnapshot(threads: order.compactMap { agents[$0]?.shell }, projects: projects)
        lock.unlock()
        continuation.yield(.snapshot(snapshot))
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self?.advance()
            }
        }
        return stream
    }

    public func detail(threadId: String) async throws -> ThreadProjection {
        lock.lock()
        defer { lock.unlock() }
        guard let agent = agents[threadId] else { throw T3Failure.http(404, "Thread not found") }
        return projection(agent)
    }

    public func send(_ command: T3Command) async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
        lock.lock()
        guard var agent = agents[command.threadId] else {
            lock.unlock()
            throw T3Failure.http(404, "Thread not found")
        }
        switch command {
        case .approve(_, let requestId, _), .answer(_, let requestId, _):
            agent.requests.removeAll { $0.id == requestId }
            agent.requestItems.removeAll { $0.requestId == requestId }
        case .stop:
            agent.requests.removeAll()
            agent.requestItems.removeAll()
            agent.shell.status = "interrupted"
            agent.shell.activityRunStatus = nil
            agent.shell.latestRunCompletedAt = Date()
        case .snooze(_, let until):
            agent.shell.snoozedUntil = until
            agent.shell.snoozedAt = Date()
        case .unsnooze:
            agent.shell.snoozedUntil = nil
        case .settle:
            agent.shell.settledOverride = "settled"
        case .unsettle:
            agent.shell.settledOverride = nil
        }
        refreshPending(&agent)
        agents[command.threadId] = agent
        let shell = agent.shell
        lock.unlock()
        emit(shell)
    }

    public func environmentId() async -> String? { "demo" }

    public func providers() -> [ProviderLimits] {
        let now = Date()
        return [
            Self.provider("claudeAgent", "Claude", nil, now, [("session", "Session", 16, 3.3), ("weekly", "Weekly", 38, 70)]),
            Self.provider("codex", "Codex", "#2563eb", now, [("session", "Session", 64, 1.6), ("weekly", "Weekly", 9, 140)]),
        ]
    }


    private func add(_ shell: ThreadShell, plan: [String], done: Int, start: Date) {
        let steps = plan.enumerated().map { index, text in
            PlanStep(id: "\(shell.id)-s\(index)", text: text,
                     status: index < done ? "completed" : index == done && shell.status == "running" ? "running" : "pending")
        }
        let activity = (0..<(shell.status == "running" ? 3 : 0)).map { index in
            Self.item(shell.id, index: index, status: index == 2 ? "running" : "completed")
        }
        agents[shell.id] = Agent(shell: shell, plan: steps, activity: activity, runStart: start)
        order.append(shell.id)
    }

    private func raiseApproval(_ id: String, kind: String, prompt: String, at: Date) {
        guard var agent = agents[id] else { return }
        let requestId = "\(id)-req-\(agent.requests.count + agent.activity.count)-\(Int(at.timeIntervalSince1970))"
        agent.requests.append(RuntimeRequest(id: requestId, kind: kind, status: "pending", createdAt: at,
                                             responseCapability: .init(type: "live")))
        agent.requestItems.append(TurnItem(id: "\(requestId)-item", type: "approval_request", runId: "\(id)-run",
                                           ordinal: 900, status: "waiting", requestId: requestId, requestKind: kind,
                                           prompt: prompt, options: [
                                               ApprovalChoice(decision: "accept", label: "Approve"),
                                               ApprovalChoice(decision: "acceptForSession", label: "Always this session"),
                                               ApprovalChoice(decision: "decline", label: "Deny"),
                                           ]))
        refreshPending(&agent)
        agents[id] = agent
    }

    private func raiseQuestion(_ id: String, at: Date) {
        guard var agent = agents[id] else { return }
        let requestId = "\(id)-question-\(Int(at.timeIntervalSince1970))"
        agent.requests.append(RuntimeRequest(id: requestId, kind: "user_input", status: "pending", createdAt: at,
                                             responseCapability: .init(type: "live")))
        agent.requestItems.append(TurnItem(id: "\(requestId)-item", type: "user_input_request", runId: "\(id)-run",
                                           ordinal: 901, status: "waiting", requestId: requestId, questions: [
                                               UserInputQuestion(id: "retries", header: "Retries",
                                                                 question: "Should retries run on every webhook, or only after a 5xx?",
                                                                 options: [QuestionOption(label: "Every webhook"),
                                                                           QuestionOption(label: "Only after a 5xx", value: "5xx")]),
                                               UserInputQuestion(id: "backoff", header: "Backoff",
                                                                 question: "What's the longest backoff between retries?",
                                                                 options: [QuestionOption(label: "30 seconds"), QuestionOption(label: "5 minutes")],
                                                                 allowCustomAnswer: true),
                                           ]))
        refreshPending(&agent)
        agents[id] = agent
    }

    private func refreshPending(_ agent: inout Agent) {
        if let first = agent.requests.first {
            agent.shell.pendingRuntimeRequest = PendingRequestSummary(id: first.id, kind: first.kind, createdAt: first.createdAt)
            if agent.shell.status == "running" { agent.shell.activityRunStatus = "waiting" }
        } else {
            agent.shell.pendingRuntimeRequest = nil
            if agent.shell.status == "running" { agent.shell.activityRunStatus = "running" }
        }
        agent.shell.updatedAt = Date()
    }

    private func advance() {
        lock.lock()
        step += 1
        var changed: [ThreadShell] = []
        for id in order {
            guard var agent = agents[id], agent.shell.status == "running", agent.requests.isEmpty else { continue }
            if let last = agent.activity.indices.last { agent.activity[last].status = "completed" }
            agent.activity.append(Self.item(id, index: agent.activity.count, status: "running"))
            if step % 2 == 0, let running = agent.plan.firstIndex(where: { $0.status == "running" }) {
                agent.plan[running].status = "completed"
                if running + 1 < agent.plan.count {
                    agent.plan[running + 1].status = "running"
                } else {
                    agent.shell.status = "completed"
                    agent.shell.activityRunStatus = nil
                    agent.shell.latestRunCompletedAt = Date()
                    agent.shell.latestVisibleMessage = VisibleMessage(role: "assistant", text: "All steps done. The suite passes 20 times in a row.")
                    if let last = agent.activity.indices.last { agent.activity[last].status = "completed" }
                }
            }
            agent.shell.updatedAt = Date()
            agents[id] = agent
            changed.append(agent.shell)
        }
        if step % 9 == 0, let target = order.first(where: { agents[$0]?.shell.status == "running" && agents[$0]?.requests.isEmpty == true }) {
            raiseApproval(target, kind: "command", prompt: "npm install --save-dev vitest", at: Date())
            if let shell = agents[target]?.shell { changed.append(shell) }
        }
        if step % 14 == 0, let finished = order.first(where: { agents[$0]?.shell.status == "completed" && !(agents[$0]?.plan.isEmpty ?? true) }) {
            restart(finished)
            if let shell = agents[finished]?.shell { changed.append(shell) }
        }
        lock.unlock()
        for shell in changed { emit(shell) }
    }

    private func restart(_ id: String) {
        guard var agent = agents[id] else { return }
        agent.shell.status = "running"
        agent.shell.activityRunStatus = "running"
        agent.runStart = Date()
        agent.shell.latestUserAuthoredMessageAt = agent.runStart
        agent.shell.latestRunRequestedAt = agent.runStart
        agent.plan = agent.plan.enumerated().map { index, step in
            PlanStep(id: "\(step.id)-r\(self.step)", text: step.text, status: index == 0 ? "running" : "pending")
        }
        agent.activity = []
        agents[id] = agent
    }

    private func emit(_ shell: ThreadShell) {
        lock.lock()
        sequence += 1
        let continuation = continuation
        lock.unlock()
        continuation?.yield(.threadUpdated(shell, archived: false))
    }

    private func projection(_ agent: Agent) -> ThreadProjection {
        let runId = "\(agent.shell.id)-run"
        let status = agent.shell.activityRunStatus ?? agent.shell.status
        let run = Run(id: runId, ordinal: 1, status: status == "idle" ? "completed" : status, requestedAt: agent.runStart,
                      startedAt: agent.runStart, completedAt: agent.shell.latestRunCompletedAt,
                      modelSelection: agent.shell.modelSelection, providerInstanceId: agent.shell.providerInstanceId)
        let plans = agent.plan.isEmpty ? [] : [Plan(id: "\(agent.shell.id)-plan-\(agent.plan.first?.id ?? "")", runId: runId,
                                                     status: "active", steps: agent.plan)]
        return ThreadProjection(
            thread: ProjectedThread(id: agent.shell.id, title: agent.shell.title, providerInstanceId: agent.shell.providerInstanceId,
                                    modelSelection: agent.shell.modelSelection, branch: agent.shell.branch),
            runs: [run], plans: plans, runtimeRequests: agent.requests,
            turnItems: agent.activity + agent.requestItems
        )
    }

    private static func item(_ id: String, index: Int, status: String) -> TurnItem {
        let entry = script[(index + id.count) % script.count]
        let isCommand = entry.1 == "command_execution"
        return TurnItem(id: "\(id)-item-\(index)", type: entry.1, runId: "\(id)-run", ordinal: index, status: status,
                        updatedAt: Date(), input: isCommand ? .string(String(entry.0.dropFirst(2))) : nil,
                        fileName: isCommand ? nil : entry.0)
    }

    private static func shell(_ id: String, _ title: String, _ project: String, provider: String, model: String,
                              branch: String = "main", status: String, start: Date? = nil, completed: Date? = nil,
                              message: String? = nil, error: String? = nil, snoozedUntil: Date? = nil) -> ThreadShell {
        ThreadShell(id: id, projectId: project, title: title, providerInstanceId: provider,
                    modelSelection: ModelSelection(instanceId: provider, model: model), branch: branch,
                    status: status, activityRunStatus: status == "running" ? "running" : nil, latestRunId: "\(id)-run",
                    latestRunRequestedAt: start, latestRunStartedAt: start, latestRunCompletedAt: completed,
                    activityRunStartedAt: start, lastError: error,
                    latestVisibleMessage: message.map { VisibleMessage(role: "assistant", text: $0) },
                    latestUserAuthoredMessageAt: start, updatedAt: completed ?? start ?? Date(), snoozedUntil: snoozedUntil,
                    snoozedAt: snoozedUntil == nil ? nil : Date().addingTimeInterval(-600))
    }

    private static func provider(_ id: String, _ name: String, _ accent: String?, _ now: Date,
                                 _ windows: [(String, String, Double, Double)]) -> ProviderLimits {
        ProviderLimits(id: id, name: name, accentHex: accent, checkedAt: now.addingTimeInterval(-60),
                       windows: windows.map { kind, label, used, hours in
                           LimitWindow(id: "\(id)-\(kind)", kind: kind, label: label, usedPercent: used,
                                       resetsAt: now.addingTimeInterval(hours * 3600))
                       },
                       note: nil)
    }
}
