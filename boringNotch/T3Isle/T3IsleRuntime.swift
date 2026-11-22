import AppKit
import Combine
import Defaults
import SwiftUI
import T3IsleCore

@MainActor
final class T3IsleRuntime: ObservableObject {
    static let shared = T3IsleRuntime()

    let model: T3IsleModel
    @Published private(set) var presence: ClosedPresence = .none
    @Published private(set) var headphones: HeadphonesConnect?
    private let headphonesPopup = HeadphonesPopup()
    private lazy var headphonesMonitor = T3HeadphonesMonitor(popup: headphonesPopup)
    private var cancellables: Set<AnyCancellable> = []
    #if DEBUG
    let debugSource: DebugSource
    #endif

    static var isDemo: Bool {
        CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.environment["T3ISLE_DEMO"] == "1"
    }

    static var isHeadphonesDemo: Bool {
        CommandLine.arguments.contains("--demo-headphones")
            || ProcessInfo.processInfo.environment["T3ISLE_DEMO_HEADPHONES"] == "1"
    }

    private init() {
        let base: T3Source = Self.isDemo ? ReplaySource(scenario: try? Scenario.named("showcase")) : LiveSource()
        #if DEBUG
        debugSource = DebugSource(base: base)
        let source: T3Source = debugSource
        #else
        let source = base
        #endif
        model = T3IsleModel(source: source, isDemo: Self.isDemo) { url in
            NSWorkspace.shared.open(url)
        }
        Publishers.CombineLatest4(
            Defaults.publisher(.t3Enabled).map(\.newValue),
            Defaults.publisher(.t3ThreadActions).map(\.newValue),
            Defaults.publisher(.t3KeepFinishedPinned).map(\.newValue),
            Defaults.publisher(.t3ShowSubagents).map(\.newValue)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] enabled, actions, pinned, subagents in
            self?.model.apply(T3Preferences(enabled: enabled, threadActions: actions, keepFinishedPinned: pinned,
                                            showSubagents: subagents))
        }
        .store(in: &cancellables)
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.presence != self.model.closedPresence else { return }
                self.presence = self.model.closedPresence
            }
            .store(in: &cancellables)
        headphonesPopup.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] next in
                withAnimation(next == nil ? T3Theme.liveActivityOut : T3Theme.liveActivityIn) { self?.headphones = next }
            }
            .store(in: &cancellables)
        Defaults.publisher(.t3HeadphonesActivity)
            .map(\.newValue)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.headphonesMonitor.setEnabled($0) }
            .store(in: &cancellables)
        if Defaults[.t3Enabled] { model.start() }
    }

    #if DEBUG
    func showHeadphones(name: String, battery: Int?, device: BluetoothAudioClass?) {
        let kind = HeadphonesKind(appleProductID: nil, classOfDevice: device?.classOfDevice, name: name)
        let level = kind.hasTwoBuds
            ? HeadphonesBattery(left: battery, right: battery)
            : HeadphonesBattery(single: battery)
        headphonesPopup.show(HeadphonesConnect(address: "debug", name: name, kind: kind, battery: level))
    }

    func hideHeadphones() {
        headphonesPopup.dismiss()
    }

    func play(_ scenario: Scenario) {
        debugSource.play(scenario)
        model.restart()
    }

    func stopReplay() {
        guard debugSource.isReplaying else { return }
        debugSource.stopReplay()
        model.restart()
    }

    var sourceKind: DebugState.T3.Source {
        debugSource.isReplaying ? .replay : Self.isDemo ? .demo : .live
    }

    var replaySources: [ReplaySource] {
        [debugSource.replay] + [debugSource.base as? ReplaySource].compactMap { $0 }
    }

    private var activeReplay: ReplaySource? {
        debugSource.isReplaying ? debugSource.replay : debugSource.base as? ReplaySource
    }

    private var replayStatus: ReplayStatus? { activeReplay?.current }

    var isSettled: Bool {
        guard Defaults[.t3Enabled], let replay = activeReplay else { return !model.isFetchingDetails }
        return replay.current?.finished == true && model.isCaughtUp(threads: replay.threads, providers: replay.providers())
    }

    var debugState: DebugState.T3 {
        model.debugState(enabled: Defaults[.t3Enabled], source: sourceKind, replay: replayStatus)
    }
    #endif
}

enum T3Tabs {
    static let openSize = CGSize(width: 640, height: 480)

    @MainActor
    static func visible(_ tabs: [TabModel]) -> [TabModel] {
        guard Defaults[.t3Enabled] else { return tabs }
        let t3 = TabModel(label: "T3", icon: Image("t3.blob"), view: .t3)
        return tabs.flatMap { $0.view == .home ? [$0, t3] : [$0] }
    }

    @MainActor
    static func barShown(shelfEmpty: Bool) -> Bool {
        NotchTab.barShown(t3Enabled: Defaults[.t3Enabled],
                          shelfEnabled: Defaults[.boringShelf],
                          shelfEmpty: shelfEmpty,
                          alwaysShowTabs: BoringViewCoordinator.shared.alwaysShowTabs)
    }

    @MainActor
    static func openingView(current: NotchViews) -> NotchViews {
        Defaults[.openingTab].tab(current: current,
                                  t3Ready: Defaults[.t3Enabled] && T3IsleRuntime.shared.model.hasAgents,
                                  shelfFirst: !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault],
                                  barShown: barShown(shelfEmpty: ShelfStateViewModel.shared.isEmpty))
    }

    static func migrateRememberLastTab() {
        let legacyKey = "openLastTabByDefault"
        if UserDefaults.standard.bool(forKey: legacyKey) { Defaults[.openingTab] = .last }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    @MainActor
    static func openSize(for view: NotchViews, base: CGSize) -> CGSize {
        view == .t3 ? openSize : base
    }

    @MainActor
    static func closedActivity() -> ClosedActivity {
        let runtime = T3IsleRuntime.shared
        let music = MusicManager.shared
        return ClosedActivity.resolve(t3: Defaults[.t3Enabled] ? runtime.presence : .none,
                                      headphones: runtime.headphones,
                                      nowPlaying: (music.isPlaying || !music.isPlayerIdle)
                                          && BoringViewCoordinator.shared.musicLiveActivityEnabled)
    }
}
