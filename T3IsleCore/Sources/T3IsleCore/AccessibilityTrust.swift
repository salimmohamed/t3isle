import Foundation

public enum AccessibilityRead: String, Codable, Sendable, CaseIterable {
    case trusted, denied, unreachable

    public init(granted: Bool) {
        self = granted ? .trusted : .denied
    }
}

public struct AccessibilityReadTicket: Comparable, Sendable {
    let number: Int

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.number < rhs.number }
}

public struct AccessibilityReadTickets: Sendable {
    private var lastNumber = 0

    public init() {}

    public mutating func issue() -> AccessibilityReadTicket {
        lastNumber += 1
        return AccessibilityReadTicket(number: lastNumber)
    }
}

public struct AccessibilityReading: Equatable, Sendable {
    public static let notificationKey = "accessibilityReading"

    public let read: AccessibilityRead
    public let ticket: AccessibilityReadTicket

    public init(read: AccessibilityRead, ticket: AccessibilityReadTicket) {
        self.read = read
        self.ticket = ticket
    }

    func isNewer(than other: AccessibilityReading?) -> Bool {
        other.map { ticket > $0.ticket } ?? true
    }
}

public enum AccessibilityGuidance: String, Codable, Sendable {
    case unchecked, trusted, denied, unreachable

    public var showsReAddHint: Bool { self == .denied }

    public var offersRequest: Bool { self != .unreachable }
}

public enum HUDReplacementEnable: Equatable, Sendable {
    case startInterceptor
    case requestAccessAndTurnOff
    case keepSaved

    public init?(read: AccessibilityRead, cancelled: Bool) {
        guard !cancelled else { return nil }
        switch read {
        case .trusted: self = .startInterceptor
        case .denied: self = .requestAccessAndTurnOff
        case .unreachable: self = .keepSaved
        }
    }
}

public enum HUDReplacementTrustChange: Equatable, Sendable {
    case startInterceptor
    case turnOff

    public init?(read: AccessibilityRead?, isOn: Bool) {
        guard isOn else { return nil }
        switch read {
        case .trusted?: self = .startInterceptor
        case .denied?: self = .turnOff
        case .unreachable?, nil: return nil
        }
    }
}

public struct AccessibilityReadChanges: Sendable {
    public private(set) var last: AccessibilityReading?

    public init() {}

    public mutating func record(_ reading: AccessibilityReading) -> Bool {
        guard reading.isNewer(than: last) else { return false }
        defer { last = reading }
        return reading.read != last?.read
    }
}

public struct AccessibilityTrust: Equatable, Sendable {
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    private var last: AccessibilityReading?

    public init() {}

    public var lastRead: AccessibilityRead? { last?.read }

    public var guidance: AccessibilityGuidance {
        switch lastRead {
        case .trusted?: .trusted
        case .denied?: .denied
        case .unreachable?: .unreachable
        case nil: .unchecked
        }
    }

    @discardableResult
    public mutating func checked(_ reading: AccessibilityReading) -> Bool {
        guard reading.isNewer(than: last) else { return false }
        last = reading
        return true
    }
}

@MainActor
public final class UnreachableReadRetry {
    public static let firstWait: TimeInterval = 1
    public static let longestWait: TimeInterval = 30

    private let clock: any T3Clock
    private let read: @MainActor () -> Void
    private var failures = 0
    private var pending: Task<Void, Never>?

    public init(clock: any T3Clock = LiveClock(), read: @escaping @MainActor () -> Void) {
        self.clock = clock
        self.read = read
    }

    public func landed(_ landed: AccessibilityRead) {
        pending?.cancel()
        pending = nil
        guard landed == .unreachable else {
            failures = 0
            return
        }
        let deadline = clock.now + Self.wait(after: failures)
        failures += 1
        pending = Task { [clock, read] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            read()
        }
    }

    static func wait(after failures: Int) -> TimeInterval {
        min(firstWait * pow(2, Double(failures)), longestWait)
    }
}
