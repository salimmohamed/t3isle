#if DEBUG
import Foundation

public final class DebugSource: T3Source, @unchecked Sendable {
    private struct Fake {
        var shell: ThreadShell
        var projection: ThreadProjection
    }

    private let base: T3Source
    private let project = ProjectShell(id: "debug", title: "debug")
    private let lock = NSLock()
    private var fakes: [String: Fake] = [:]
    private var counter = 0
    private var continuation: AsyncStream<ShellUpdate>.Continuation?

    public init(base: T3Source) {
        self.base = base
    }

    public func updates() async -> AsyncStream<ShellUpdate> {
        let upstream = await base.updates()
        let (stream, continuation) = AsyncStream<ShellUpdate>.makeStream()
        lock.withLock { self.continuation = continuation }
        let forward = Task { [weak self] in
            for await update in upstream {
                guard let self else { return continuation.finish() }
                self.lock.withLock { _ = continuation.yield(self.merged(update)) }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forward.cancel() }
        return stream
    }

    public func detail(threadId: String) async throws -> ThreadProjection {
        if let fake = lock.withLock({ fakes[threadId] }) { return fake.projection }
        return try await base.detail(threadId: threadId)
    }

    public func send(_ command: T3Command) async throws {
        let shell: ThreadShell? = lock.withLock {
            guard var fake = fakes[command.threadId] else { return nil }
            fake.projection.runtimeRequests.removeAll()
            fake.projection.turnItems.removeAll { $0.requestId != nil }
            fake.shell.pendingRuntimeRequest = nil
            fake.shell.status = "completed"
            fake.shell.activityRunStatus = nil
            fake.shell.latestRunCompletedAt = Date()
            fake.shell.updatedAt = Date()
            fakes[command.threadId] = fake
            return fake.shell
        }
        guard let shell else { return try await base.send(command) }
        emit(shell)
    }

    public func environmentId() async -> String? { await base.environmentId() }

    public func providers() -> [ProviderLimits] { base.providers() }

    @discardableResult
    public func raiseQuestion() -> String {
        let id = nextId("question")
        let now = Date()
        let requestId = "\(id)-request"
        var shell = Self.shell(id, title: "Debug question", status: "running", at: now)
        shell.activityRunStatus = "waiting"
        shell.pendingRuntimeRequest = PendingRequestSummary(id: requestId, kind: "user_input", createdAt: now)
        let request = RuntimeRequest(id: requestId, kind: "user_input", status: "pending", createdAt: now,
                                     responseCapability: .init(type: "live"))
        let item = TurnItem(id: "\(requestId)-item", type: "user_input_request", runId: "\(id)-run", ordinal: 1,
                            status: "waiting", requestId: requestId, questions: [
                                UserInputQuestion(id: "color", header: "Border",
                                                  question: "Does the attention border show around the notch?",
                                                  options: [QuestionOption(label: "Yes"), QuestionOption(label: "No")],
                                                  allowCustomAnswer: true),
                            ])
        add(Fake(shell: shell, projection: Self.projection(shell, plan: [], requests: [request], items: [item])))
        return id
    }

    @discardableResult
    public func finishPlan(after delay: Duration = .seconds(2)) -> String {
        let id = nextId("plan")
        let steps = ["Read the brief", "Make the change", "Run the checks"]
        let running = steps.enumerated().map { index, text in
            PlanStep(id: "\(id)-s\(index)", text: text, status: index < 2 ? "completed" : "running")
        }
        let shell = Self.shell(id, title: "Debug plan", status: "running", at: Date())
        add(Fake(shell: shell, projection: Self.projection(shell, plan: running, requests: [], items: [])))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.complete(id, steps: running)
        }
        return id
    }

    private func complete(_ id: String, steps: [PlanStep]) {
        let shell: ThreadShell? = lock.withLock {
            guard var fake = fakes[id] else { return nil }
            fake.shell.status = "completed"
            fake.shell.activityRunStatus = nil
            fake.shell.latestRunCompletedAt = Date()
            fake.shell.updatedAt = Date()
            fake.shell.latestVisibleMessage = VisibleMessage(role: "assistant", text: "All three steps are done.")
            let done = steps.map { PlanStep(id: $0.id, text: $0.text, status: "completed") }
            fake.projection = Self.projection(fake.shell, plan: done, requests: [], items: [])
            fakes[id] = fake
            return fake.shell
        }
        if let shell { emit(shell) }
    }

    private func nextId(_ kind: String) -> String {
        lock.withLock {
            counter += 1
            return "debug-\(kind)-\(counter)"
        }
    }

    private func add(_ fake: Fake) {
        lock.withLock {
            fakes[fake.shell.id] = fake
            continuation?.yield(.projectUpdated(project))
            continuation?.yield(.threadUpdated(fake.shell, archived: false))
        }
    }

    private func emit(_ shell: ThreadShell) {
        lock.withLock { _ = continuation?.yield(.threadUpdated(shell, archived: false)) }
    }

    private func merged(_ update: ShellUpdate) -> ShellUpdate {
        guard case .snapshot(var snapshot) = update else { return update }
        let shells = fakes.values.map(\.shell)
        guard !shells.isEmpty else { return update }
        snapshot.threads += shells
        snapshot.projects.append(project)
        return .snapshot(snapshot)
    }

    private static func shell(_ id: String, title: String, status: String, at date: Date) -> ThreadShell {
        ThreadShell(id: id, projectId: "debug", title: title, providerInstanceId: "claudeAgent",
                    modelSelection: ModelSelection(instanceId: "claudeAgent", model: "claude-opus-5-5"), branch: "debug",
                    status: status, activityRunStatus: status == "running" ? "running" : nil, latestRunId: "\(id)-run",
                    latestRunStartedAt: date, activityRunStartedAt: date, updatedAt: date)
    }

    private static func projection(_ shell: ThreadShell, plan: [PlanStep], requests: [RuntimeRequest],
                                   items: [TurnItem]) -> ThreadProjection {
        let runId = "\(shell.id)-run"
        let status = shell.activityRunStatus ?? shell.status
        let run = Run(id: runId, ordinal: 1, status: status, requestedAt: shell.latestRunStartedAt,
                      startedAt: shell.latestRunStartedAt, completedAt: shell.latestRunCompletedAt,
                      modelSelection: shell.modelSelection, providerInstanceId: shell.providerInstanceId)
        let plans = plan.isEmpty ? [] : [Plan(id: "\(shell.id)-plan", runId: runId, status: "active", steps: plan)]
        return ThreadProjection(
            thread: ProjectedThread(id: shell.id, title: shell.title, providerInstanceId: shell.providerInstanceId,
                                    modelSelection: shell.modelSelection, branch: shell.branch),
            runs: [run], plans: plans, runtimeRequests: requests, turnItems: items
        )
    }
}
#endif
