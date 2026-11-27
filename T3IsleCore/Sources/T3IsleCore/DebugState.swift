#if DEBUG
import Foundation

public struct DebugState: Codable, Equatable, Sendable {
    public enum Notch: String, Codable, Sendable { case open, closed }

    public enum Activity: String, Codable, Sendable {
        case none, t3, nowPlaying, headphones, pomodoro

        public init(_ activity: ClosedActivity) {
            switch activity {
            case .none: self = .none
            case .t3: self = .t3
            case .nowPlaying: self = .nowPlaying
            case .headphones: self = .headphones
            case .pomodoro: self = .pomodoro
            }
        }
    }

    public struct Headphones: Codable, Equatable, Sendable {
        public let name: String
        public let kind: String
    }

    public struct HeadphonesMonitor: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable { case off, listening, watching }

        public let bluetooth: BluetoothAccess
        public let status: Status

        public init(bluetooth: BluetoothAccess, status: Status) {
            self.bluetooth = bluetooth
            self.status = status
        }
    }

    public struct Pomodoro: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let phase: PomodoroPhase
        public let running: Bool

        public init(enabled: Bool, phase: PomodoroPhase, running: Bool) {
            self.enabled = enabled
            self.phase = phase
            self.running = running
        }
    }

    public struct Clipboard: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let watching: Bool
        public let items: Int

        public init(enabled: Bool, watching: Bool, items: Int) {
            self.enabled = enabled
            self.watching = watching
            self.items = items
        }
    }

    public struct T3: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable { case live, demo, replay }
        public enum Connection: String, Codable, Sendable {
            case connecting, live, offline

            public init(_ state: ConnectionState) {
                switch state {
                case .connecting: self = .connecting
                case .live: self = .live
                case .offline: self = .offline
                }
            }
        }

        public struct Thread: Codable, Equatable, Sendable {
            public let id: String
            public let title: String
            public let project: String
            public let mood: String
            public let snoozed: Bool
            public let environment: String?
        }

        public struct Prompt: Codable, Equatable, Sendable {
            public let id: String
            public let threadId: String
            public let kind: String
            public let title: String
        }

        public struct Agent: Codable, Equatable, Sendable {
            public let id: String
            public let state: String
        }

        public struct Banner: Codable, Equatable, Sendable {
            public let threadId: String
            public let steps: Int
        }

        public struct Window: Codable, Equatable, Sendable {
            public let kind: String
            public let usedPercent: Double
        }

        public struct Provider: Codable, Equatable, Sendable {
            public let id: String
            public let windows: [Window]
        }

        public let enabled: Bool
        public let source: Source
        public let replay: ReplayStatus?
        public let connection: Connection
        public let presence: String
        public let threads: [Thread]
        public let prompts: [Prompt]
        public let agents: [Agent]
        public let banner: Banner?
        public let providers: [Provider]

        public init(enabled: Bool, source: Source, replay: ReplayStatus?, connection: ConnectionState,
                    presence: ClosedPresence, threads: [T3Thread], prompts: [PendingPrompt], cards: [AgentCard],
                    banner: PlanBanner?, providers: [ProviderLimits]) {
            self.enabled = enabled
            self.source = source
            self.replay = replay
            self.connection = Connection(connection)
            self.presence = "\(presence)"
            self.threads = threads.map {
                Thread(id: $0.id, title: $0.title, project: $0.project, mood: "\($0.mood)", snoozed: $0.isSnoozed,
                       environment: $0.environment?.label)
            }
            self.prompts = prompts.map {
                Prompt(id: $0.id, threadId: $0.threadId, kind: $0.isApproval ? "approval" : "question", title: $0.title)
            }
            agents = cards.map { Agent(id: $0.id, state: "\($0.state)") }
            self.banner = banner.map { Banner(threadId: $0.threadId, steps: $0.stepCount) }
            self.providers = providers.map { provider in
                Provider(id: provider.id, windows: provider.windows.map { Window(kind: $0.kind, usedPercent: $0.usedPercent) })
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(source, forKey: .source)
            try container.encode(replay, forKey: .replay)
            try container.encode(connection, forKey: .connection)
            try container.encode(presence, forKey: .presence)
            try container.encode(threads, forKey: .threads)
            try container.encode(prompts, forKey: .prompts)
            try container.encode(agents, forKey: .agents)
            try container.encode(banner, forKey: .banner)
            try container.encode(providers, forKey: .providers)
        }
    }

    public let notch: Notch
    public let tab: NotchTab
    public let tabBarShown: Bool
    public let settingsOpen: Bool
    public let closedActivity: Activity
    public let headphones: Headphones?
    public let notchViewModels: Int
    public let headphonesMonitor: HeadphonesMonitor
    public let hudAccessibility: AccessibilityGuidance
    public let accessibilityOverride: AccessibilityRead?
    public let hudReplacement: Bool
    public let pomodoro: Pomodoro
    public let clipboardHistory: Clipboard
    public let t3: T3

    public init(notch: Notch, tab: NotchTab, tabBarShown: Bool, settingsOpen: Bool, closedActivity: ClosedActivity,
                headphones: HeadphonesConnect?, notchViewModels: Int, headphonesMonitor: HeadphonesMonitor, hudAccessibility: AccessibilityGuidance,
                accessibilityOverride: AccessibilityRead?, hudReplacement: Bool, pomodoro: Pomodoro,
                clipboardHistory: Clipboard, t3: T3) {
        self.notch = notch
        self.tab = tab
        self.tabBarShown = tabBarShown
        self.settingsOpen = settingsOpen
        self.closedActivity = Activity(closedActivity)
        self.headphones = headphones.map { Headphones(name: $0.name, kind: "\($0.kind)") }
        self.notchViewModels = notchViewModels
        self.headphonesMonitor = headphonesMonitor
        self.hudAccessibility = hudAccessibility
        self.accessibilityOverride = accessibilityOverride
        self.hudReplacement = hudReplacement
        self.pomodoro = pomodoro
        self.clipboardHistory = clipboardHistory
        self.t3 = t3
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notch, forKey: .notch)
        try container.encode(tab, forKey: .tab)
        try container.encode(tabBarShown, forKey: .tabBarShown)
        try container.encode(settingsOpen, forKey: .settingsOpen)
        try container.encode(closedActivity, forKey: .closedActivity)
        try container.encode(headphones, forKey: .headphones)
        try container.encode(notchViewModels, forKey: .notchViewModels)
        try container.encode(headphonesMonitor, forKey: .headphonesMonitor)
        try container.encode(hudAccessibility, forKey: .hudAccessibility)
        try container.encode(accessibilityOverride, forKey: .accessibilityOverride)
        try container.encode(hudReplacement, forKey: .hudReplacement)
        try container.encode(pomodoro, forKey: .pomodoro)
        try container.encode(clipboardHistory, forKey: .clipboardHistory)
        try container.encode(t3, forKey: .t3)
    }

    public static func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

extension PomodoroTimer {
    public func debugState(enabled: Bool) -> DebugState.Pomodoro {
        DebugState.Pomodoro(enabled: enabled, phase: phase, running: isRunning)
    }
}

extension ClipboardHistory {
    public func debugState(enabled: Bool) -> DebugState.Clipboard {
        DebugState.Clipboard(enabled: enabled, watching: isWatching, items: items.count)
    }
}

extension T3IsleModel {
    public func debugState(enabled: Bool, source: DebugState.T3.Source, replay: ReplayStatus?) -> DebugState.T3 {
        DebugState.T3(enabled: enabled, source: source, replay: replay, connection: connection, presence: closedPresence,
                      threads: threads, prompts: prompts, cards: allCards, banner: banner, providers: providers)
    }
}
#endif
