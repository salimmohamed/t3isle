import Foundation

public struct LimitWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, kind: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public func remaining(at now: Date) -> Double {
        if let resetsAt, resetsAt <= now { return 100 }
        return 100 - min(max(usedPercent, 0), 100)
    }
}

public struct ProviderLimits: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let accentHex: String?
    public let checkedAt: Date?
    public let windows: [LimitWindow]
    public let note: String?

    public init(id: String, name: String, accentHex: String?, checkedAt: Date?, windows: [LimitWindow], note: String?) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.checkedAt = checkedAt
        self.windows = windows
        self.note = note
    }

    public func tightest(at now: Date, kind: String? = nil) -> LimitWindow? {
        let ofKind = windows.filter { $0.kind == kind }
        return (ofKind.isEmpty ? windows : ofKind).min { $0.remaining(at: now) < $1.remaining(at: now) }
    }
}

public enum QuotaWindowChoice: String, Codable, CaseIterable, Sendable {
    case session, weekly, tightest

    public var title: String {
        switch self {
        case .session: "5-hour window"
        case .weekly: "Weekly window"
        case .tightest: "Whichever is lowest"
        }
    }

    public var kind: String? { self == .tightest ? nil : rawValue }
}

public final class UsageLimitsReader: @unchecked Sendable {
    private struct ProviderFile: Decodable {
        struct Limits: Decodable {
            let checkedAt: String?
            let windows: [Window]?
            let unavailable: Unavailable?
        }
        struct Unavailable: Decodable {
            let reason: String?
            let message: String?
        }
        struct Window: Decodable {
            let id: String
            let kind: String?
            let label: String?
            let usedPercent: Double?
            let resetsAt: String?
        }
        let displayName: String?
        let enabled: Bool?
        let accentColor: String?
        let usageLimits: Limits?
    }

    private let directory: URL
    private let lock = NSLock()
    private var cache: (stamp: [String: Date], value: [ProviderLimits]) = ([:], [])

    public init(home: T3Home) {
        directory = home.cachesDirectory
    }

    public func read() -> [ProviderLimits] {
        lock.lock()
        defer { lock.unlock() }
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []).filter { $0.pathExtension == "json" }

        var stamp: [String: Date] = [:]
        for file in files {
            stamp[file.lastPathComponent] =
                (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        if stamp == cache.stamp { return cache.value }

        let previous = cache.value
        let result = files.compactMap { file -> ProviderLimits? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return Self.parse(data, id: file.deletingPathExtension().lastPathComponent, previous: previous)
        }
        let sorted = Self.ordered(result)
        cache = (stamp, sorted)
        return sorted
    }

    static func parse(_ data: Data, id: String, previous: [ProviderLimits]) -> ProviderLimits? {
        guard let parsed = try? JSONDecoder().decode(ProviderFile.self, from: data),
              parsed.enabled != false,
              let limits = parsed.usageLimits
        else { return nil }
        var checkedAt = WireDate.parse(limits.checkedAt)
        var note: String?
        var windows: [LimitWindow] = (limits.windows ?? []).compactMap { window in
            guard let used = window.usedPercent else { return nil }
            return LimitWindow(id: window.id, kind: window.kind ?? "", label: window.label ?? window.id,
                               usedPercent: used, resetsAt: WireDate.parse(window.resetsAt))
        }
        if windows.isEmpty {
            guard let unavailable = limits.unavailable, unavailable.reason != "unsupported" else { return nil }
            let last = previous.first { $0.id == id && !$0.windows.isEmpty }
            windows = last?.windows ?? []
            checkedAt = last?.checkedAt
            note = unavailable.message ?? "T3 could not check these limits."
        }
        return ProviderLimits(id: id, name: parsed.displayName ?? id, accentHex: parsed.accentColor,
                              checkedAt: checkedAt, windows: windows, note: note)
    }

    static func ordered(_ providers: [ProviderLimits]) -> [ProviderLimits] {
        let order = ["claudeAgent": 0, "codex": 1]
        return providers.sorted { (order[$0.id] ?? 9, $0.name) < (order[$1.id] ?? 9, $1.name) }
    }
}
