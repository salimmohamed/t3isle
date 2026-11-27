import Foundation

public enum AccessibilityRead: String, Codable, Sendable, CaseIterable {
    case trusted, denied, unreachable

    public static let notificationKey = "accessibilityRead"

    public init(granted: Bool) {
        self = granted ? .trusted : .denied
    }
}

public enum AccessibilityGuidance: String, Codable, Sendable {
    case unchecked, trusted, denied, unreachable

    public var showsReAddHint: Bool { self == .denied }

    public var offersRequest: Bool { self != .unreachable }
}

public enum HUDReplacementEnable: Equatable, Sendable {
    case startInterceptor
    case turnOff(requestingAccess: Bool)

    public init?(read: AccessibilityRead, cancelled: Bool) {
        guard !cancelled else { return nil }
        switch read {
        case .trusted: self = .startInterceptor
        case .denied: self = .turnOff(requestingAccess: true)
        case .unreachable: self = .turnOff(requestingAccess: false)
        }
    }
}

public struct AccessibilityReadChanges: Sendable {
    private var last: AccessibilityRead?

    public init() {}

    public mutating func record(_ read: AccessibilityRead) -> Bool {
        defer { last = read }
        return read != last
    }
}

public struct AccessibilityTrust: Equatable, Sendable {
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public private(set) var lastRead: AccessibilityRead?

    public init() {}

    public var guidance: AccessibilityGuidance {
        switch lastRead {
        case .trusted?: .trusted
        case .denied?: .denied
        case .unreachable?: .unreachable
        case nil: .unchecked
        }
    }

    public mutating func checked(_ read: AccessibilityRead) {
        lastRead = read
    }
}
