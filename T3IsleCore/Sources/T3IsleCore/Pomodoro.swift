import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case idle, focus
    case rest = "break"
}

@MainActor
public final class PomodoroTimer: ObservableObject {
    public static let focusLength: TimeInterval = 25 * 60
    public static let breakLength: TimeInterval = 5 * 60

    @Published public private(set) var phase: PomodoroPhase = .idle
    @Published public private(set) var endsAt: Date?
    @Published public private(set) var pausedLeft: TimeInterval?

    private let clock: any T3Clock
    private(set) var phaseEnd: Task<Void, Never>?

    public init(clock: any T3Clock = LiveClock()) {
        self.clock = clock
    }

    public var isActive: Bool { phase != .idle }
    public var isRunning: Bool { endsAt != nil }

    public func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return pausedLeft ?? Self.focusLength
    }

    public func countdown(at now: Date) -> String {
        Format.elapsed(remaining(at: now).rounded(.up))
    }

    public func start() {
        if phase == .idle {
            phase = .focus
            run(until: clock.now + Self.focusLength)
        } else if let pausedLeft {
            run(until: clock.now + pausedLeft)
        }
    }

    public func pause() {
        guard let endsAt else { return }
        stopWaiting()
        pausedLeft = max(0, endsAt.timeIntervalSince(clock.now))
        self.endsAt = nil
    }

    public func reset() {
        stopWaiting()
        phase = .idle
        endsAt = nil
        pausedLeft = nil
    }

    private func run(until end: Date) {
        stopWaiting()
        pausedLeft = nil
        endsAt = end
        phaseEnd = Task { [weak self, clock] in
            try? await clock.sleep(until: end)
            guard !Task.isCancelled else { return }
            self?.phaseEnded(at: end)
        }
    }

    private func phaseEnded(at end: Date) {
        guard endsAt == end else { return }
        if phase == .focus {
            phase = .rest
            run(until: end + Self.breakLength)
        } else {
            reset()
        }
    }

    private func stopWaiting() {
        phaseEnd?.cancel()
        phaseEnd = nil
    }
}
