import Foundation

public enum AccessibilityRead: String, Codable, Sendable, CaseIterable {
    case trusted, denied, unreachable

    public init(granted: Bool) {
        self = granted ? .trusted : .denied
    }

    public var granted: Bool? {
        switch self {
        case .trusted: true
        case .denied: false
        case .unreachable: nil
        }
    }
}

public enum AccessibilityGuidance: String, Codable, Sendable {
    case unchecked, trusted, denied, unreachable

    public var showsReAddHint: Bool { self == .denied }
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
