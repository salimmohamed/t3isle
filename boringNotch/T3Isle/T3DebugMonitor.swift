#if DEBUG
import AppKit
import Combine
import T3IsleCore

@MainActor
final class T3DebugMonitor {
    static let shared = T3DebugMonitor()

    private let folders = StateFolders.current
    private let log = DebugEventLog(folders: .current)
    private var cancellables: Set<AnyCancellable> = []

    func record(_ event: String, _ attributes: [String: String] = [:]) {
        log.record(event, attributes)
    }

    func start(notch: BoringViewModel) {
        let runtime = T3IsleRuntime.shared
        let coordinator = BoringViewCoordinator.shared
        let log = log
        do {
            try folders.recordRunPid(ProcessInfo.processInfo.processIdentifier)
        } catch {
            record("run.failed", ["message": error.localizedDescription])
        }
        record("app.launched", ["pid": String(ProcessInfo.processInfo.processIdentifier), "version": appVersion,
                                "source": runtime.sourceKind.rawValue])
        for replay in runtime.replaySources {
            replay.onProgress { progress in
                switch progress {
                case .started(let scenario, let steps): log.record("replay.started", ["scenario": scenario, "steps": String(steps)])
                case .finished(let scenario): log.record("replay.finished", ["scenario": scenario])
                }
            }
        }
        runtime.model.$connection
            .map(DebugState.T3.Connection.init)
            .removeDuplicates()
            .sink { log.record("connection.changed", ["state": $0.rawValue]) }
            .store(in: &cancellables)
        notch.$notchState
            .removeDuplicates()
            .dropFirst()
            .sink { log.record($0 == .open ? "notch.opened" : "notch.closed") }
            .store(in: &cancellables)
        coordinator.$currentView
            .removeDuplicates()
            .dropFirst()
            .sink { log.record("tab.changed", ["tab": $0.rawValue]) }
            .store(in: &cancellables)
        Publishers.Merge3(runtime.objectWillChange, MusicManager.shared.objectWillChange, coordinator.objectWillChange)
            .receive(on: RunLoop.main)
            .map { _ in DebugState.Activity(T3Tabs.closedActivity()) }
            .prepend(DebugState.Activity(T3Tabs.closedActivity()))
            .removeDuplicates()
            .dropFirst()
            .sink { log.record("activity.changed", ["closedActivity": $0.rawValue]) }
            .store(in: &cancellables)
        runtime.model.$prompts
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { log.record("prompts.changed", ["count": String($0)]) }
            .store(in: &cancellables)
        runtime.model.$banner
            .compactMap { $0 }
            .sink { log.record("banner.shown", ["threadId": $0.threadId]) }
            .store(in: &cancellables)
    }

    func writeStateWhenSettled(notch: BoringViewModel) {
        Task { @MainActor in
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while !T3IsleRuntime.shared.isSettled, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            do {
                try writeState(notch: notch, settled: T3IsleRuntime.shared.isSettled)
            } catch {
                record("state.failed", ["message": error.localizedDescription])
            }
        }
    }

    private func writeState(notch: BoringViewModel, settled: Bool) throws {
        let runtime = T3IsleRuntime.shared
        let state = DebugState(notch: notch.notchState == .open ? .open : .closed,
                               tab: BoringViewCoordinator.shared.currentView,
                               settingsOpen: SettingsWindowController.shared.window?.isVisible == true,
                               closedActivity: T3Tabs.closedActivity(),
                               headphones: runtime.headphones,
                               t3: runtime.debugState)
        try folders.createLogs()
        try DebugState.encoded(state).write(to: folders.stateFile, options: .atomic)
        record("state.written", ["path": folders.stateFile.path, "settled": String(settled)])
    }
}
#endif
