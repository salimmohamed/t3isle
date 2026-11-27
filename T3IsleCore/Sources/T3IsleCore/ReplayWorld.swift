import Foundation

struct ReplayWorld: Sendable {
    private(set) var threads: [ThreadShell] = []
    private(set) var projects: [ProjectShell] = []
    private(set) var projections: [String: ThreadProjection] = [:]
    private(set) var providers: [ProviderLimits] = []

    var snapshot: ShellSnapshot { ShellSnapshot(threads: threads, projects: projects) }

    mutating func apply(_ event: ReplayEvent) -> ShellUpdate? {
        switch event {
        case .shell(let update):
            apply(update)
            return update
        case .detail(let projection):
            projections[projection.thread.id] = projection
            return nil
        case .provider(let limits):
            providers = UsageLimitsReader.ordered(providers.filter { $0.id != limits.id } + [limits])
            return nil
        }
    }

    private mutating func apply(_ update: ShellUpdate) {
        switch update {
        case .snapshot(let snapshot):
            threads = snapshot.threads
            projects = snapshot.projects
        case .threadUpdated(let shell, archived: true):
            threads.removeAll { $0.id == shell.id }
        case .threadUpdated(let shell, archived: false):
            Self.upsert(shell, into: &threads)
        case .threadRemoved(let id):
            threads.removeAll { $0.id == id }
            projections[id] = nil
        case .projectUpdated(let project):
            Self.upsert(project, into: &projects)
        case .projectRemoved(let id):
            projects.removeAll { $0.id == id }
        case .disconnected, .unreadable:
            break
        }
    }

    mutating func respond(to command: T3Command, at now: Date) throws -> ShellUpdate {
        guard let index = threads.firstIndex(where: { $0.id == command.threadId }) else {
            throw T3Failure.http(404, "Thread not found")
        }
        var shell = threads[index]
        var projection = projections[shell.id]
        switch command {
        case .approve(_, let requestId, _), .answer(_, let requestId, _):
            projection?.runtimeRequests.removeAll { $0.id == requestId }
            projection?.turnItems.removeAll { $0.requestId == requestId }
            Self.refreshPending(&shell, &projection)
        case .stop:
            projection?.runtimeRequests.removeAll()
            projection?.turnItems.removeAll { $0.requestId != nil }
            shell.status = "interrupted"
            shell.activityRunStatus = nil
            shell.latestRunCompletedAt = now
            Self.refreshPending(&shell, &projection)
            projection?.finishLatestRun(status: "interrupted", at: now)
        case .snooze(_, let until):
            shell.snoozedUntil = until
            shell.snoozedAt = now
        case .unsnooze:
            shell.snoozedUntil = nil
        case .settle:
            shell.settledOverride = "settled"
        case .unsettle:
            shell.settledOverride = nil
        }
        shell.updatedAt = now
        threads[index] = shell
        projections[shell.id] = projection
        return .threadUpdated(shell, archived: false)
    }

    private static func refreshPending(_ shell: inout ThreadShell, _ projection: inout ThreadProjection?) {
        let next = projection?.runtimeRequests
            .filter { $0.status == "pending" }
            .min { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        shell.pendingRuntimeRequest = next.map { PendingRequestSummary(id: $0.id, kind: $0.kind, createdAt: $0.createdAt) }
        guard shell.status == "running" else { return }
        shell.activityRunStatus = next == nil ? "running" : "waiting"
        projection?.setLatestRun(status: shell.activityRunStatus ?? shell.status)
    }

    private static func upsert<Item: Identifiable>(_ item: Item, into items: inout [Item]) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }
}

private extension ThreadProjection {
    mutating func setLatestRun(status: String) {
        guard let index = latestRunIndex else { return }
        runs[index].status = status
    }

    mutating func finishLatestRun(status: String, at date: Date) {
        guard let index = latestRunIndex else { return }
        runs[index].status = status
        runs[index].completedAt = date
    }

    var latestRunIndex: Int? {
        runs.indices.max { (runs[$0].ordinal ?? 0) < (runs[$1].ordinal ?? 0) }
    }
}
