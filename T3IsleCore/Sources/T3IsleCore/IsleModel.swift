import Combine
import Foundation

public struct T3Preferences: Equatable, Sendable {
    public var enabled = true
    public var threadActions = true
    public var keepFinishedPinned = true
    public var showSubagents = false

    public init(enabled: Bool = true, threadActions: Bool = true, keepFinishedPinned: Bool = true,
                showSubagents: Bool = false) {
        self.enabled = enabled
        self.threadActions = threadActions
        self.keepFinishedPinned = keepFinishedPinned
        self.showSubagents = showSubagents
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

public enum ClosedPresence: Equatable, Sendable {
    case none, idle, threads, alert
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
    private let clock: any T3Clock
    private let opener: (URL) -> Void
    @Published private var preferences = T3Preferences()
    @Published private var details: [String: AgentDetail] = [:]
    private var shells: [String: ThreadShell] = [:]
    private var projects: [String: ProjectShell] = [:]
    private var linkedShells: [String: ThreadShell] = [:]
    private var linkedProjects: [String: ProjectShell] = [:]
    private var linkedRefreshedAt: Date?
    private var readingLinked = false
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
    private var session = 0

    public init(source: T3Source, isDemo: Bool = false, clock: any T3Clock = LiveClock(),
                opener: @escaping (URL) -> Void) {
        self.source = source
        self.isDemo = isDemo
        self.clock = clock
        self.opener = opener
    }

    public var hasAgents: Bool { !threads.isEmpty || !agentGroups.isEmpty }
    public var needsAttention: Bool { !prompts.isEmpty }
    public var workingCount: Int { threads.filter { $0.mood.isBusy }.count }

    public var closedPresence: ClosedPresence {
        guard preferences.enabled, connection == .live else { return .none }
        if needsAttention || banner != nil { return .alert }
        return threads.isEmpty ? .idle : .threads
    }
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
                try? await self.clock.sleep(until: self.clock.now + self.tickInterval)
            }
        }
        let session = session
        Task {
            let environment = await source.environmentId()
            if self.session == session { environmentId = environment }
        }
    }

    public func stop() {
        streamTask?.cancel()
        tickTask?.cancel()
        streamTask = nil
        tickTask = nil
        scheduledFetch.values.forEach { $0.cancel() }
        scheduledFetch.removeAll()
    }

    #if DEBUG
    public var isFetchingDetails: Bool { !fetching.isEmpty || !scheduledFetch.isEmpty }

    public func isCaughtUp(threads: [ThreadShell], providers: [ProviderLimits]) -> Bool {
        shells == Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) && self.providers == providers
            && !isFetchingDetails
    }

    public func restart() {
        stop()
        session += 1
        threads = []
        providers = []
        prompts = []
        agentGroups = []
        selectedAgentId = nil
        banner = nil
        notice = nil
        completedSteps = [:]
        shells = [:]
        projects = [:]
        linkedShells = [:]
        linkedProjects = [:]
        linkedRefreshedAt = nil
        readingLinked = false
        details = [:]
        detailPrompts = [:]
        lastFetch = [:]
        fetching = []
        rawThreads = []
        changes = [:]
        answered = [:]
        draftAnswers = [:]
        stopping = [:]
        finished = [:]
        dismissed = []
        wasWorking = []
        knownPromptIds = []
        environmentId = nil
        heldBy = nil
        reconnectDelay = 1
        motionIsAction = false
        start()
    }
    #endif

    public func apply(_ preferences: T3Preferences) {
        guard preferences != self.preferences else { return }
        self.preferences = preferences
        if preferences.enabled { start() } else { stop() }
        if !preferences.keepFinishedPinned { finished.removeAll() }
        scheduleRefresh()
        publish()
    }

    static let linkedInterval: TimeInterval = 10

    private var allShells: [String: ThreadShell] {
        linkedShells.merging(shells) { _, local in local }
    }

    private var allProjects: [String: ProjectShell] {
        linkedProjects.merging(projects) { _, local in local }
    }

    private func linkedEnvironment(of threadId: String) -> String? {
        allShells[threadId]?.linkedEnvironment?.id
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
            try? await clock.sleep(until: clock.now + reconnectDelay)
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
            refreshProviders()
            for shell in snapshot.threads where wantsDetail(shell) { requestDetail(shell.id, urgent: true) }
        case .threadUpdated(let shell, let archived):
            if archived { shells[shell.id] = nil } else { shells[shell.id] = shell }
            if wantsDetail(shell) || details[shell.id] != nil {
                requestDetail(shell.id, urgent: shell.pendingRuntimeRequest != nil && detailPrompts[shell.id]?.isEmpty != false)
            }
        case .threadRemoved(let id):
            shells[id] = nil
            forgetDetail(id)
        case .projectUpdated(let project):
            projects[project.id] = project
        case .projectRemoved(let id):
            projects[id] = nil
        case .disconnected(let failure):
            connection = .offline(failure.localizedDescription)
        case .unreadable:
            return
        }
        publish()
    }

    private func isShown(_ shell: ThreadShell) -> Bool {
        InboxBuilder.hasPendingRequest(shell) || (!shell.isSideChat && (preferences.showSubagents || !shell.isSubagent))
    }

    private var visibleShells: [String: ThreadShell] {
        allShells.filter { isShown($0.value) }
    }

    private func wantsDetail(_ shell: ThreadShell) -> Bool {
        guard isShown(shell) else { return false }
        guard InboxBuilder.belongsInInbox(shell) else { return false }
        let mood = InboxBuilder.mood(shell)
        if mood == .needsYou || shell.id == selectedAgentId { return true }
        let following = mood == .working || mood == .waiting || finished[shell.id] != nil
        return following && (shell.linkedEnvironment == nil || expanded)
    }

    private func refreshProviders() {
        let fresh = source.providers()
        if fresh != providers { providers = fresh }
    }

    private func tick() async {
        refreshProviders()
        let now = clock.now
        answered = answered.filter { key, at in
            now.timeIntervalSince(at) < 45 || draftAnswers.keys.contains { key.hasPrefix("\($0)#") }
        }
        stopping = stopping.filter { now.timeIntervalSince($0.value) < 20 }
        for shell in allShells.values where wantsDetail(shell) { requestDetail(shell.id, urgent: false) }
        publish(prune: true)
        refreshLinked(now: now)
    }

    private func refreshLinked(now: Date) {
        guard !readingLinked, now >= (linkedRefreshedAt ?? .distantPast) + Self.linkedInterval else { return }
        readingLinked = true
        let session = session
        Task { [weak self, source, clock] in
            let read = await source.linked()
            guard let self, self.session == session else { return }
            self.readingLinked = false
            self.linkedRefreshedAt = clock.now
            if let read { self.absorbLinked(read) }
        }
    }

    private func absorbLinked(_ read: LinkedRead) {
        let unanswered = linkedShells.values.filter { shell in
            shell.linkedEnvironment.map { read.reachable.contains($0.id) && !read.answered.contains($0.id) } == true
        }
        let fresh = Dictionary((unanswered + read.threads).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in linkedShells.keys where fresh[id] == nil && shells[id] == nil { forgetDetail(id) }
        linkedShells = fresh
        linkedProjects.merge(read.projects.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for shell in fresh.values where !InboxBuilder.awaitsAnswer(shell) { detailPrompts[shell.id] = nil }
        for shell in fresh.values where wantsDetail(shell) && (details[shell.id] == nil || asksUnread(shell)) {
            requestDetail(shell.id, urgent: true)
        }
        publish()
    }

    private func asksUnread(_ shell: ThreadShell) -> Bool {
        InboxBuilder.awaitsAnswer(shell) && detailPrompts[shell.id]?.isEmpty != false
    }

    private func scheduleRefresh() {
        for shell in linkedShells.values where shells[shell.id] == nil && !wantsDetail(shell) { forgetDetail(shell.id) }
        for shell in allShells.values where wantsDetail(shell) { requestDetail(shell.id, urgent: true) }
    }

    private func requestDetail(_ threadId: String, urgent: Bool) {
        let settled: TimeInterval = linkedEnvironment(of: threadId) == nil ? (expanded || !prompts.isEmpty ? 0.75 : 2) : Self.linkedInterval
        let interval: TimeInterval = urgent ? 0.25 : settled
        let due = (lastFetch[threadId] ?? .distantPast) + interval
        if clock.now >= due {
            fetchDetail(threadId)
        } else if scheduledFetch[threadId] == nil {
            scheduledFetch[threadId] = Task { [weak self, clock] in
                try? await clock.sleep(until: due)
                guard !Task.isCancelled else { return }
                self?.scheduledFetch[threadId] = nil
                self?.fetchDetail(threadId)
            }
        }
    }

    private func fetchDetail(_ threadId: String) {
        guard !fetching.contains(threadId) else { return }
        fetching.insert(threadId)
        lastFetch[threadId] = clock.now
        let session = session
        let environment = linkedEnvironment(of: threadId)
        Task { [weak self, source] in
            let projection = try? await source.detail(threadId: threadId, in: environment)
            guard let self, self.session == session else { return }
            self.fetching.remove(threadId)
            guard let projection else { return }
            self.absorb(projection)
        }
    }

    private func absorb(_ projection: ThreadProjection) {
        let id = projection.thread.id
        guard let shell = allShells[id], isShown(shell), shell.linkedEnvironment == nil || wantsDetail(shell) else {
            forgetDetail(id)
            return
        }
        let detail = DetailBuilder.detail(projection)
        let previous = details[id]
        if let plan = detail.plan, plan.isComplete, let before = previous?.plan, before.planId == plan.planId, !before.isComplete {
            showBanner(threadId: id, steps: plan.steps.count)
        }
        if let plan = detail.plan {
            let done = Set(plan.steps.filter { $0.status == "completed" }.map(\.id))
            if completedSteps[id] != done { completedSteps[id] = done }
        }
        if details[id] != detail { details[id] = detail }
        let project = shell.projectId.flatMap { allProjects[$0]?.title } ?? ""
        detailPrompts[id] = DetailBuilder.prompts(projection, title: shell.title, project: project)
        publish()
    }

    private func forgetDetail(_ threadId: String) {
        if details[threadId] != nil { details[threadId] = nil }
        detailPrompts[threadId] = nil
    }

    private func showBanner(threadId: String, steps: Int) {
        let title = allShells[threadId]?.title ?? "Plan"
        let banner = PlanBanner(threadId: threadId, threadTitle: title, stepCount: steps)
        self.banner = banner
        let hideAt = clock.now + 4
        Task { [weak self, clock] in
            try? await clock.sleep(until: hideAt)
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }

    private func publish(prune: Bool = false) {
        let names = Dictionary(providers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let now = clock.now
        var built = InboxBuilder(providerNames: names).threads(from: Array(visibleShells.values), projects: allProjects, now: now)
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
            let now = clock.now
            changes = changes.filter { id, entry in
                guard now.timeIntervalSince(entry.done ?? entry.at) < (entry.done == nil ? 60 : 20) else { return false }
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
        let visible = visibleShells
        let live = visible.values.filter { InboxBuilder.hasPendingRequest($0) }
        let liveRequestIds = Set(live.compactMap { $0.pendingRuntimeRequest?.id })
        let candidates = detailPrompts.values.flatMap { $0 }
            .filter { liveRequestIds.contains($0.requestId) || visible[$0.threadId].map(InboxBuilder.awaitsAnswer) == true }
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
        let visible = visibleShells
        let active = threads.filter { $0.mood == .working || $0.mood == .waiting || $0.mood == .needsYou }
        let activeIds = Set(active.map(\.id))
        if preferences.keepFinishedPinned {
            for id in wasWorking.subtracting(activeIds) where !dismissed.contains(id) && visible[id] != nil {
                finished[id] = finished[id] ?? now
            }
        }
        for id in activeIds {
            finished[id] = nil
            dismissed.remove(id)
        }
        wasWorking = activeIds
        let doneIds = finished.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
        let doneThreads = doneIds.compactMap { id in
            threads.first { $0.id == id } ?? visible[id].map {
                InboxBuilder().thread(from: $0, project: $0.projectId.flatMap { allProjects[$0] }, now: now)
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
        let session = session
        let linked = threadId.flatMap(linkedEnvironment(of:))
        Task {
            var local = environmentId
            if local == nil { local = await source.environmentId() }
            guard self.session == session else { return }
            environmentId = local
            let environment = linked ?? local
            guard environment != ReplaySource.environment else { return }
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
        stopping[threadId] = clock.now
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
        perform(thread, .snoozed(until: until), notice: "Snoozed until \(Format.clock(until, now: clock.now))")
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
        case .woke: reverse = .snoozed(until: undo.thread.snoozedUntil ?? clock.now.addingTimeInterval(3600))
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

    public func didShowThreadChanges() {
        motionIsAction = false
    }

    private func markAnswered(_ ids: [String]) {
        let now = clock.now
        for id in ids { answered[id] = now }
        publishPrompts()
    }

    private func unmark(requestId: String) {
        answered = answered.filter { !$0.key.hasPrefix(requestId) }
        draftAnswers[requestId] = nil
        publishPrompts()
    }

    private func send(_ command: T3Command, failure: @escaping @MainActor () -> Void) {
        let environment = linkedEnvironment(of: command.threadId)
        Task { [weak self, source] in
            do {
                try await source.send(command, in: environment)
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
        changes[thread.id] = (change, clock.now, nil)
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
        let environment = thread.environment?.id
        Task { [weak self, source, clock] in
            do {
                try await source.send(command, in: environment)
                if self?.changes[thread.id]?.change == change { self?.changes[thread.id]?.done = clock.now }
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
        let hideAt = clock.now + (notice.isError ? 8 : 6)
        Task { [weak self, clock] in
            try? await clock.sleep(until: hideAt)
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }
}
