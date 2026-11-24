import Foundation

public enum AccessibilityGuidance: String, Codable, Sendable {
    case untrusted, stale, trusted
}

public struct AccessibilityTrust: Equatable, Sendable {
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public private(set) var trusted: Bool?
    public private(set) var asked: Bool
    public private(set) var awaitingReturn = false

    public init(asked: Bool) {
        self.asked = asked
    }

    public var guidance: AccessibilityGuidance {
        switch trusted {
        case true?: .trusted
        case false? where asked && !awaitingReturn: .stale
        default: .untrusted
        }
    }

    public mutating func requested() {
        asked = true
        awaitingReturn = true
    }

    public mutating func checked(trusted: Bool) {
        self.trusted = trusted
        guard trusted else { return }
        asked = false
        awaitingReturn = false
    }

    public mutating func appBecameActive(trusted: Bool) {
        awaitingReturn = false
        checked(trusted: trusted)
    }
}
