#if DEBUG
import AppKit
import Combine
import T3IsleCore

@MainActor
final class T3DebugMonitor {
    static let shared = T3DebugMonitor()

    let paths: DebugPaths
    private let log: DebugEventLog
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "T3 Isle"
        paths = DebugPaths(appName: name)
        log = DebugEventLog(paths: paths)
    }

    func record(_ event: String, _ attributes: [String: String] = [:]) {
        log.record(event, attributes)
    }

    func start(notch: BoringViewModel) {
        let runtime = T3IsleRuntime.shared
        let coordinator = BoringViewCoordinator.shared
        let log = log
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

    func writeState(notch: BoringViewModel) throws {
        let runtime = T3IsleRuntime.shared
        let state = DebugState(notch: notch.notchState == .open ? .open : .closed,
                               tab: BoringViewCoordinator.shared.currentView,
                               settingsOpen: SettingsWindowController.shared.window?.isVisible == true,
                               closedActivity: T3Tabs.closedActivity(),
                               headphones: runtime.headphones,
                               t3: runtime.debugState)
        try paths.create()
        try DebugState.encoded(state).write(to: paths.state, options: .atomic)
        record("state.written", ["path": paths.state.path])
    }
}
#endif
