import Combine
import Foundation

public struct T3Preferences: Equatable, Sendable {
    public var enabled = true
    public var threadActions = true
    public var keepFinishedPinned = true

    public init(enabled: Bool = true, threadActions: Bool = true, keepFinishedPinned: Bool = true) {
        self.enabled = enabled
        self.threadActions = threadActions
        self.keepFinishedPinned = keepFinishedPinned
    }
}

public enum ConnectionState: Equatable, Sendable {
    case connecting
    case live
    case offline(String)
}

public enum ThreadChange: Equatable, Sendable {
    case settled
    case unsettled(T3Thread, index: Int)
    case snoozed(until: Date)
    case woke
}

public struct ActionNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
    public var isError = false
    public var undo: UndoAction?

    public struct UndoAction: Equatable, Sendable {
        let thread: T3Thread
        let change: ThreadChange
        let index: Int
    }

    public static func == (lhs: ActionNotice, rhs: ActionNotice) -> Bool { lhs.id == rhs.id }
}

public struct AgentCard: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable { case working, needsYou, waiting, done, stopping }

    public let thread: T3Thread
    public let state: State
    public let detail: AgentDetail?

    public var id: String { thread.id }
}

public struct ProjectGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let cards: [AgentCard]
}

public struct PlanBanner: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let threadId: String
    public let threadTitle: String
    public let stepCount: Int

    public static func == (lhs: PlanBanner, rhs: PlanBanner) -> Bool { lhs.id == rhs.id }
}

@MainActor
public final class T3IsleModel: ObservableObject {
    @Published public private(set) var threads: [T3Thread] = []
    @Published public private(set) var providers: [ProviderLimits] = []
    @Published public private(set) var prompts: [PendingPrompt] = []
    @Published public private(set) var agentGroups: [ProjectGroup] = []
    @Published public private(set) var selectedAgentId: String?
    @Published public private(set) var banner: PlanBanner?
    @Published public private(set) var notice: ActionNotice?
    @Published public private(set) var connection: ConnectionState = .connecting
    @Published public private(set) var promptArrivals = 0
    @Published public private(set) var completedSteps: [String: Set<String>] = [:]
    @Published public var expanded = false {
        didSet { if expanded != oldValue { scheduleRefresh() } }
    }

    public let isDemo: Bool
    public private(set) var motionIsAction = false

    private let source: T3Source
    private let opener: (URL) -> Void
    private var preferences = T3Preferences()
    private var shells: [String: ThreadShell] = [:]
    private var projects: [String: ProjectShell] = [:]
    private var details: [String: AgentDetail] = [:]
    private var detailPrompts: [String: [PendingPrompt]] = [:]
    private var lastFetch: [String: Date] = [:]
    private var fetching: Set<String> = []
    private var scheduledFetch: [String: Task<Void, Never>] = [:]
    private var rawThreads: [T3Thread] = []
    private var changes: [String: (change: ThreadChange, at: Date, done: Date?)] = [:]
    private var answered: [String: Date] = [:]
    private var draftAnswers: [String: [String: QuestionAnswer]] = [:]
    private var stopping: [String: Date] = [:]
    private var finished: [String: Date] = [:]
    private var dismissed: Set<String> = []
    private var wasWorking: Set<String> = []
    private var knownPromptIds: Set<String> = []
    private var streamTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var environmentId: String?
    private var heldBy: String?
    private var reconnectDelay: TimeInterval = 1

    public init(source: T3Source, isDemo: Bool = false, opener: @escaping (URL) -> Void) {
        self.source = source
        self.isDemo = isDemo
        self.opener = opener
    }

    public var hasAgents: Bool { !threads.isEmpty || !agentGroups.isEmpty }
    public var needsAttention: Bool { !prompts.isEmpty }
    public var workingCount: Int { threads.filter { $0.mood.isBusy }.count }
    public var allCards: [AgentCard] { agentGroups.flatMap(\.cards) }

    public func detail(for threadId: String) -> AgentDetail? { details[threadId] }

    public var selectedCard: AgentCard? {
        let cards = allCards
        return cards.first { $0.id == selectedAgentId } ?? cards.first
    }

    public func start() {
        guard streamTask == nil else { return }
        connection = .connecting
        streamTask = Task { [weak self] in await self?.consume() }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: UInt64(self.tickInterval * 1_000_000_000))
            }
        }
        Task { environmentId = await source.environmentId() }
    }

    public func stop() {
        streamTask?.cancel()
        tickTask?.cancel()
        streamTask = nil
        tickTask = nil
        scheduledFetch.values.forEach { $0.cancel() }
        scheduledFetch.removeAll()
    }

    public func apply(_ preferences: T3Preferences) {
        guard preferences != self.preferences else { return }
        self.preferences = preferences
        if preferences.enabled { start() } else { stop() }
        if !preferences.keepFinishedPinned { finished.removeAll() }
        publish()
    }

    private var tickInterval: TimeInterval {
        if !prompts.isEmpty || expanded { return 1.5 }
        return workingCount > 0 ? 3 : 10
    }

    private func consume() async {
        while !Task.isCancelled {
            let stream = await source.updates()
            for await update in stream {
                if Task.isCancelled { return }
                handle(update)
                if case .disconnected = update { break }
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            reconnectDelay = min(reconnectDelay * 2, 30)
        }
    }

    private func handle(_ update: ShellUpdate) {
        switch update {
        case .snapshot(let snapshot):
            shells = Dictionary(snapshot.threads.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            projects = Dictionary(snapshot.projects.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            connection = .live
            reconnectDelay = 1
            for shell in snapshot.threads where wantsDetail(shell) { requestDetail(shell.id, urgent: true) }
        case .threadUpdated(let shell, let archived):
            if archived { shells[shell.id] = nil } else { shells[shell.id] = shell }
            if wantsDetail(shell) || details[shell.id] != nil {
                requestDetail(shell.id, urgent: shell.pendingRuntimeRequest != nil && detailPrompts[shell.id]?.isEmpty != false)
            }
        case .threadRemoved(let id):
            shells[id] = nil
            details[id] = nil
            detailPrompts[id] = nil
        case .projectUpdated(let project):
            projects[project.id] = project
        case .projectRemoved(let id):
            projects[id] = nil
        case .resyncNeeded:
            break
        case .disconnected(let failure):
            connection = .offline(failure.localizedDescription)
        }
        publish()
    }

    private func wantsDetail(_ shell: ThreadShell) -> Bool {
        if shell.archivedAt == nil, shell.deletedAt == nil, InboxBuilder.hasPendingRequest(shell) { return true }
        guard InboxBuilder.belongsInInbox(shell) else { return false }
        let mood = InboxBuilder.mood(shell)
        return mood == .needsYou || mood == .working || mood == .waiting || shell.id == selectedAgentId
            || finished[shell.id] != nil
    }

    private func tick() async {
        let fresh = source.providers()
        if fresh != providers { providers = fresh }
        let now = Date()
        answered = answered.filter { now.timeIntervalSince($0.value) < 45 }
        stopping = stopping.filter { now.timeIntervalSince($0.value) < 20 }
        for shell in shells.values where wantsDetail(shell) { requestDetail(shell.id, urgent: false) }
        publish(prune: true)
    }

    private func scheduleRefresh() {
        for shell in shells.values where wantsDetail(shell) { requestDetail(shell.id, urgent: true) }
    }

    private func requestDetail(_ threadId: String, urgent: Bool) {
        let interval: TimeInterval = urgent ? 0.25 : (expanded || !prompts.isEmpty ? 0.75 : 2)
        let elapsed = Date().timeIntervalSince(lastFetch[threadId] ?? .distantPast)
        if elapsed >= interval {
            fetchDetail(threadId)
        } else if scheduledFetch[threadId] == nil {
            let wait = interval - elapsed
            scheduledFetch[threadId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.scheduledFetch[threadId] = nil
                self?.fetchDetail(threadId)
            }
        }
    }

    private func fetchDetail(_ threadId: String) {
        guard !fetching.contains(threadId) else { return }
        fetching.insert(threadId)
        lastFetch[threadId] = Date()
        Task { [weak self, source] in
            let projection = try? await source.detail(threadId: threadId)
            guard let self else { return }
            self.fetching.remove(threadId)
            guard let projection else { return }
            self.absorb(projection)
        }
    }

    private func absorb(_ projection: ThreadProjection) {
        let id = projection.thread.id
        let detail = DetailBuilder.detail(projection)
        let previous = details[id]
        if let plan = detail.plan, plan.isComplete, let before = previous?.plan, before.planId == plan.planId, !before.isComplete {
            showBanner(threadId: id, steps: plan.steps.count)
        }
        if let plan = detail.plan {
            let done = Set(plan.steps.filter { $0.status == "completed" }.map(\.id))
            if completedSteps[id] != done { completedSteps[id] = done }
        }
        details[id] = detail
        let shell = shells[id]
        let title = shell?.title ?? projection.thread.title ?? "Untitled"
        let project = shell?.projectId.flatMap { projects[$0]?.title } ?? ""
        detailPrompts[id] = DetailBuilder.prompts(projection, title: title, project: project)
        publish()
    }

    private func showBanner(threadId: String, steps: Int) {
        let title = shells[threadId]?.title ?? "Plan"
        let banner = PlanBanner(threadId: threadId, threadTitle: title, stepCount: steps)
        self.banner = banner
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }

    private func publish(prune: Bool = false) {
        let names = Dictionary(providers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        var built = InboxBuilder(providerNames: names).threads(from: Array(shells.values), projects: projects, now: now)
        for index in built.indices {
            let id = built[index].id
            if built[index].mood.isBusy, let line = details[id]?.latestLine {
                built[index].line = line
            } else if built[index].mood == .needsYou, let prompt = detailPrompts[id]?.first {
                built[index].line = (prompt.detail ?? prompt.title).components(separatedBy: .newlines).first
            }
        }
        if heldBy == nil || Self.sameLayout(rawThreads, built) {
            rawThreads = built
        } else if let held = heldBy, let index = rawThreads.firstIndex(where: { $0.id == held }),
                  let fresh = built.first(where: { $0.id == held }) {
            rawThreads[index] = fresh
        }
        publishThreads(prune: prune)
        publishPrompts()
        publishAgents(now: now)
    }

    private func publishThreads(prune: Bool) {
        let byId = Dictionary(rawThreads.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if prune && !isDemo {
            changes = changes.filter { id, entry in
                guard Date().timeIntervalSince(entry.done ?? entry.at) < (entry.done == nil ? 60 : 20) else { return false }
                guard entry.done != nil else { return true }
                return !Self.shows(entry.change, byId[id])
            }
        }
        var list = rawThreads
        let restored = changes.values.compactMap { entry -> (thread: T3Thread, index: Int)? in
            guard case .unsettled(let thread, let index) = entry.change, byId[thread.id] == nil else { return nil }
            return (thread, index)
        }
        for item in restored.sorted(by: { $0.index < $1.index }) {
            list.insert(item.thread, at: min(item.index, list.count))
        }
        for (id, entry) in changes {
            switch entry.change {
            case .settled: list.removeAll { $0.id == id }
            case .unsettled: break
            case .snoozed(let until):
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].snoozedUntil = until }
            case .woke:
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].snoozedUntil = nil }
            }
        }
        if threads != list { threads = list }
    }

    private func publishPrompts() {
        let live = shells.values.filter { InboxBuilder.hasPendingRequest($0) }
        let liveRequestIds = Set(live.compactMap { $0.pendingRuntimeRequest?.id })
        let candidates = detailPrompts.values.flatMap { $0 }
            .filter { liveRequestIds.contains($0.requestId) || (shells[$0.threadId]?.pendingRuntimeRequest != nil) }
        let pending = Self.ordered(candidates.filter { answered[$0.id] == nil })
        answered = answered.filter { key, _ in candidates.contains { $0.id == key } }
        let ids = Set(pending.map(\.id))
        if !ids.subtracting(knownPromptIds).isEmpty { promptArrivals += 1 }
        knownPromptIds = ids
        if prompts != pending { prompts = pending }
    }

    static func ordered(_ prompts: [PendingPrompt]) -> [PendingPrompt] {
        prompts.enumerated().sorted { lhs, rhs in
            let left = (lhs.element.createdAt ?? .distantPast, lhs.element.threadId, lhs.element.requestId)
            let right = (rhs.element.createdAt ?? .distantPast, rhs.element.threadId, rhs.element.requestId)
            if left != right { return left < right }
            return questionIndex(lhs.element) < questionIndex(rhs.element)
        }
        .map(\.element)
    }

    private static func questionIndex(_ prompt: PendingPrompt) -> Int {
        if case .question(_, let index, _) = prompt.kind { return index }
        return -1
    }

    private func publishAgents(now: Date) {
        let active = threads.filter { $0.mood == .working || $0.mood == .waiting || $0.mood == .needsYou }
        let activeIds = Set(active.map(\.id))
        if preferences.keepFinishedPinned {
            for id in wasWorking.subtracting(activeIds) where !dismissed.contains(id) && shells[id] != nil {
                finished[id] = finished[id] ?? now
            }
        }
        for id in activeIds {
            finished[id] = nil
            dismissed.remove(id)
        }
        wasWorking = activeIds
        let doneThreads = finished.keys.compactMap { id in
            threads.first { $0.id == id } ?? shells[id].map {
                InboxBuilder().thread(from: $0, project: $0.projectId.flatMap { projects[$0] }, now: now)
            }
        }
        let cards = active.map { thread in
            AgentCard(thread: thread, state: cardState(thread), detail: details[thread.id])
        } + doneThreads.map { AgentCard(thread: $0, state: .done, detail: details[$0.id]) }
        var order: [String] = []
        var grouped: [String: [AgentCard]] = [:]
        for card in cards {
            let key = card.thread.projectId ?? card.thread.project
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(card)
        }
        let groups = order.map { key in
            ProjectGroup(id: key, title: grouped[key]?.first?.thread.project.nilIfEmpty ?? "Other", cards: grouped[key] ?? [])
        }
        if agentGroups != groups { agentGroups = groups }
        if let selected = selectedAgentId, !cards.contains(where: { $0.id == selected }) { selectedAgentId = nil }
    }

    private func cardState(_ thread: T3Thread) -> AgentCard.State {
        if stopping[thread.id] != nil { return .stopping }
        switch thread.mood {
        case .needsYou: return .needsYou
        case .waiting: return .waiting
        default: return .working
        }
    }

    private static func shows(_ change: ThreadChange, _ thread: T3Thread?) -> Bool {
        switch change {
        case .settled: thread == nil
        case .unsettled: thread != nil
        case .snoozed: thread?.snoozedUntil != nil
        case .woke: thread?.snoozedUntil == nil
        }
    }

    private static func section(_ thread: T3Thread) -> Int {
        thread.mood.isBusy ? 0 : thread.snoozedUntil == nil ? 1 : 2
    }

    private static func sameLayout(_ lhs: [T3Thread], _ rhs: [T3Thread]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.id == $1.id && section($0) == section($1) }
    }

    public func select(_ threadId: String) {
        selectedAgentId = threadId
        requestDetail(threadId, urgent: true)
    }

    public func dismissFinished(_ threadId: String) {
        finished[threadId] = nil
        dismissed.insert(threadId)
        publish()
    }

    public func open(_ threadId: String?) {
        if let threadId {
            finished[threadId] = nil
            dismissed.insert(threadId)
            publish()
        }
        guard !isDemo else { return }
        Task {
            var environment = environmentId
            if environment == nil { environment = await source.environmentId() }
            environmentId = environment
            if let threadId, let environment,
               let url = URL(string: "t3code://threads/\(environment)/\(T3ServerClient.pathComponent(threadId))") {
                opener(url)
            } else if let url = URL(string: "t3code://") {
                opener(url)
            }
        }
    }

    public func respond(_ prompt: PendingPrompt, decision: ApprovalDecision) {
        markAnswered([prompt.id])
        send(.approve(threadId: prompt.threadId, requestId: prompt.requestId, decision: decision),
             failure: { [weak self] in self?.unmark(requestId: prompt.requestId) })
    }

    public func answer(_ prompt: PendingPrompt, with answer: QuestionAnswer) {
        guard case .question(let question, _, _) = prompt.kind else { return }
        var drafts = draftAnswers[prompt.requestId] ?? [:]
        drafts[question.id] = answer
        draftAnswers[prompt.requestId] = drafts
        markAnswered([prompt.id])
        let siblings = (detailPrompts[prompt.threadId] ?? []).filter { $0.requestId == prompt.requestId }
        let questionIds = siblings.compactMap { sibling -> String? in
            if case .question(let item, _, _) = sibling.kind { return item.id }
            return nil
        }
        guard questionIds.allSatisfy({ drafts[$0] != nil }) else { return }
        draftAnswers[prompt.requestId] = nil
        send(.answer(threadId: prompt.threadId, requestId: prompt.requestId, answers: drafts),
             failure: { [weak self] in self?.unmark(requestId: prompt.requestId) })
    }

    public func interrupt(_ threadId: String) {
        stopping[threadId] = Date()
        publish()
        send(.stop(threadId: threadId), failure: { [weak self] in
            self?.stopping[threadId] = nil
            self?.publish()
        })
    }

    public func settle(_ thread: T3Thread) {
        perform(thread, .settled, notice: "Settled")
    }

    public func snooze(_ thread: T3Thread, until: Date) {
        perform(thread, .snoozed(until: until), notice: "Snoozed until \(Format.clock(until, now: Date()))")
    }

    public func wake(_ thread: T3Thread) {
        perform(thread, .woke, notice: "Back in your inbox")
    }

    public func undo() {
        guard let undo = notice?.undo else { return }
        let reverse: ThreadChange
        switch undo.change {
        case .settled: reverse = .unsettled(undo.thread, index: undo.index)
        case .snoozed: reverse = .woke
        case .woke: reverse = .snoozed(until: undo.thread.snoozedUntil ?? Date().addingTimeInterval(3600))
        case .unsettled: reverse = .settled
        }
        perform(undo.thread, reverse, notice: "Undone", undoable: false)
    }

    public func hold(_ threadId: String, _ hold: Bool) {
        if hold {
            heldBy = threadId
        } else if heldBy == threadId {
            heldBy = nil
            publish()
        }
    }

    public func signOut() {
        notice = nil
        Task { await source.signOut() }
    }

    public func didShowThreadChanges() {
        motionIsAction = false
    }

    private func markAnswered(_ ids: [String]) {
        let now = Date()
        for id in ids { answered[id] = now }
        publishPrompts()
    }

    private func unmark(requestId: String) {
        answered = answered.filter { !$0.key.hasPrefix(requestId) }
        draftAnswers[requestId] = nil
        publishPrompts()
    }

    private func send(_ command: T3Command, failure: @escaping @MainActor () -> Void) {
        Task { [weak self, source] in
            do {
                try await source.send(command)
                self?.requestDetail(command.threadId, urgent: true)
            } catch {
                failure()
                self?.show(ActionNotice(text: "Couldn't do that: \(error.localizedDescription)", isError: true))
            }
        }
    }

    private func perform(_ thread: T3Thread, _ change: ThreadChange, notice text: String, undoable: Bool = true) {
        let index = rawThreads.firstIndex { $0.id == thread.id } ?? 0
        if heldBy == thread.id { heldBy = nil }
        guard preferences.threadActions else {
            show(ActionNotice(text: T3Failure.actionsOff.localizedDescription, isError: true))
            return
        }
        changes[thread.id] = (change, Date(), nil)
        motionIsAction = true
        publishThreads(prune: false)
        let notice = ActionNotice(text: text, undo: undoable ? .init(thread: thread, change: change, index: index) : nil)
        show(notice)
        let command: T3Command
        switch change {
        case .settled: command = .settle(threadId: thread.id)
        case .unsettled: command = .unsettle(threadId: thread.id)
        case .snoozed(let until): command = .snooze(threadId: thread.id, until: until)
        case .woke: command = .unsnooze(threadId: thread.id)
        }
        Task { [weak self, source] in
            do {
                try await source.send(command)
                if self?.changes[thread.id]?.change == change { self?.changes[thread.id]?.done = Date() }
            } catch {
                guard let self else { return }
                if self.changes[thread.id]?.change == change { self.changes[thread.id] = nil }
                self.motionIsAction = true
                self.publishThreads(prune: false)
                self.show(ActionNotice(text: "Couldn't do that: \(error.localizedDescription)", isError: true))
            }
        }
    }

    private func show(_ notice: ActionNotice) {
        self.notice = notice
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: notice.isError ? 8_000_000_000 : 6_000_000_000)
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }
}
