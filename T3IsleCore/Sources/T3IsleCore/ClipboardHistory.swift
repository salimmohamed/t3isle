import Foundation

@MainActor
public protocol ClipboardSource: AnyObject {
    var changeCount: Int { get }
    var types: [String] { get }
    func string() -> String?
    func setString(_ string: String)
}

@MainActor
public final class ClipboardHistory: ObservableObject {
    public static let limit = 20
    public static let pollInterval: TimeInterval = 0.5
    public static let skippedTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    @Published public private(set) var items: [String] = []

    private let pasteboard: any ClipboardSource
    private let clock: any T3Clock
    private var seenChange: Int?
    private(set) var polling: Task<Void, Never>?

    public init(pasteboard: any ClipboardSource, clock: any T3Clock = LiveClock()) {
        self.pasteboard = pasteboard
        self.clock = clock
    }

    public var isWatching: Bool { polling != nil }

    public func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    public func copy(_ text: String) {
        pasteboard.setString(text)
        seenChange = pasteboard.changeCount
        record(text)
    }

    public static func preview(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func start() {
        guard polling == nil else { return }
        seenChange = pasteboard.changeCount
        polling = Task { [weak self, clock] in
            while true {
                do { try await clock.sleep(until: clock.now + Self.pollInterval) } catch { return }
                guard !Task.isCancelled, let self else { return }
                self.check()
            }
        }
    }

    private func stop() {
        polling?.cancel()
        polling = nil
        seenChange = nil
        items = []
    }

    private func check() {
        let change = pasteboard.changeCount
        guard change != seenChange else { return }
        seenChange = change
        guard Self.skippedTypes.isDisjoint(with: pasteboard.types),
              let text = pasteboard.string(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        record(text)
    }

    private func record(_ text: String) {
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }
}
