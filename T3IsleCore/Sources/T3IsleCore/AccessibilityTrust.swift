import Foundation

public enum AccessibilityGuidance: String, Codable, Sendable {
    case untrusted, stale, trusted
}

public struct AccessibilityTrust: Equatable, Sendable {
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public private(set) var trusted: Bool?
    public private(set) var awaitingReturn = false

    public init() {}

    public var guidance: AccessibilityGuidance {
        switch trusted {
        case true?: .trusted
        case false? where !awaitingReturn: .stale
        default: .untrusted
        }
    }

    public mutating func requested() {
        awaitingReturn = true
    }

    public mutating func checked(trusted: Bool) {
        self.trusted = trusted
        if trusted { awaitingReturn = false }
    }

    public mutating func appBecameActive(trusted: Bool) {
        awaitingReturn = false
        checked(trusted: trusted)
    }
}
