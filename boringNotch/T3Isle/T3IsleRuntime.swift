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

    static var isDemo: Bool {
        CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.environment["T3ISLE_DEMO"] == "1"
    }

    static var isHeadphonesDemo: Bool {
        CommandLine.arguments.contains("--demo-headphones")
            || ProcessInfo.processInfo.environment["T3ISLE_DEMO_HEADPHONES"] == "1"
    }

    private init() {
        let source: T3Source = Self.isDemo ? DemoSource() : LiveSource()
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
}

enum T3Tabs {
    static let openSize = CGSize(width: 640, height: 480)

    @MainActor
    static func visible(_ tabs: [TabModel]) -> [TabModel] {
        guard Defaults[.t3Enabled] else { return tabs }
        return [TabModel(label: "T3", icon: Image("t3.blob"), view: .t3)] + tabs
    }

    @MainActor
    static var isAvailable: Bool { Defaults[.t3Enabled] }

    @MainActor
    static func defaultView(fallback: NotchViews) -> NotchViews {
        guard Defaults[.t3Enabled], T3IsleRuntime.shared.model.hasAgents else { return fallback }
        return .t3
    }

    @MainActor
    static func openSize(for view: NotchViews, base: CGSize) -> CGSize {
        view == .t3 ? openSize : base
    }

    @MainActor
    static func closedActivity(nowPlaying: Bool) -> ClosedActivity {
        let runtime = T3IsleRuntime.shared
        return ClosedActivity.resolve(t3: Defaults[.t3Enabled] ? runtime.presence : .none,
                                      headphones: Defaults[.t3HeadphonesActivity] ? runtime.headphones : nil,
                                      nowPlaying: nowPlaying)
    }
}
