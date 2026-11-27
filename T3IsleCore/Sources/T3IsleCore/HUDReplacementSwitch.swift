import Foundation
import Observation

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

@MainActor
@Observable
public final class HUDReplacementSwitch {
    public enum Output: Equatable, Sendable {
        case startInterceptor
        case stopInterceptor
        case requestAccess
        case turnOff
    }

    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let firstRetryWait: TimeInterval = 1
    static let longestRetryWait: TimeInterval = 30

    private var newest: AccessibilityReading?
    @ObservationIgnored public var apply: @MainActor (Output) -> Void = { _ in }
    @ObservationIgnored private let clock: any T3Clock
    @ObservationIgnored private let read: @MainActor () async -> AccessibilityReading
    @ObservationIgnored private var isOn = false
    @ObservationIgnored private var paneIsOpen = false
    @ObservationIgnored private var lastSwitchOn = 0
    @ObservationIgnored private var undecidedSwitchOn: Int?
    @ObservationIgnored private var lastReadID = 0
    @ObservationIgnored private var readsInFlight: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var unreachableReads = 0
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private(set) var nextRetry: Date?

    public init(clock: any T3Clock = LiveClock(), read: @escaping @MainActor () async -> AccessibilityReading) {
        self.clock = clock
        self.read = read
    }

    private var lastRead: AccessibilityRead? { newest?.read }

    public var guidance: AccessibilityGuidance {
        switch lastRead {
        case .trusted?: .trusted
        case .denied?: .denied
        case .unreachable?: .unreachable
        case nil: .unchecked
        }
    }

    public var isSettled: Bool { readsInFlight.isEmpty }

    public func switched(isOn: Bool) {
        self.isOn = isOn
        guard isOn else {
            undecidedSwitchOn = nil
            apply(.stopInterceptor)
            stopRetryWhenUnwanted()
            return
        }
        lastSwitchOn += 1
        undecidedSwitchOn = lastSwitchOn
        startRead(deciding: lastSwitchOn)
    }

    public func hudPane(isOpen: Bool) {
        paneIsOpen = isOpen
        if isOpen {
            check()
        } else {
            stopRetryWhenUnwanted()
        }
    }

    public func check() {
        startRead(deciding: nil)
    }

    public func landed(_ reading: AccessibilityReading) {
        guard reading.isNewer(than: newest) else { return }
        let previous = newest?.read
        newest = reading
        retryIfUnreachable(reading.read)
        guard isOn, undecidedSwitchOn == nil, reading.read != previous else { return }
        follow(reading.read)
    }

    func isReading(_ id: Int) -> Bool {
        readsInFlight[id] != nil
    }

    func readFinished(_ id: Int) async {
        await readsInFlight[id]?.value
    }

    func retryRan() async {
        await retry?.value
    }

    private func startRead(deciding switchOn: Int?) {
        lastReadID += 1
        let id = lastReadID
        readsInFlight[id] = Task { [read] in
            landed(await read())
            if let switchOn { decide(switchOn) }
            readsInFlight[id] = nil
        }
    }

    private func decide(_ switchOn: Int) {
        guard undecidedSwitchOn == switchOn else { return }
        undecidedSwitchOn = nil
        guard let lastRead else { return }
        if lastRead == .denied { apply(.requestAccess) }
        follow(lastRead)
    }

    private func follow(_ read: AccessibilityRead) {
        switch read {
        case .trusted: apply(.startInterceptor)
        case .denied: turnOff()
        case .unreachable: break
        }
    }

    private func turnOff() {
        isOn = false
        apply(.turnOff)
        stopRetryWhenUnwanted()
    }

    private var wantsRetry: Bool { isOn || paneIsOpen }

    private func retryIfUnreachable(_ read: AccessibilityRead) {
        cancelRetry()
        guard read == .unreachable, wantsRetry else {
            unreachableReads = 0
            return
        }
        let deadline = clock.now + Self.retryWait(after: unreachableReads)
        unreachableReads += 1
        nextRetry = deadline
        retry = Task { [clock] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            retry = nil
            nextRetry = nil
            check()
        }
    }

    private func stopRetryWhenUnwanted() {
        guard !wantsRetry else { return }
        cancelRetry()
        unreachableReads = 0
    }

    private func cancelRetry() {
        retry?.cancel()
        retry = nil
        nextRetry = nil
    }

    static func retryWait(after unreachableReads: Int) -> TimeInterval {
        min(firstRetryWait * pow(2, Double(unreachableReads)), longestRetryWait)
    }
}
