import Foundation

public enum AccessibilityGuidance: String, Codable, Sendable {
    case untrusted, stale, trusted
}

public struct AccessibilityTrust: Equatable, Sendable {
    public static let settingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    public private(set) var trusted: Bool?

    public init() {}

    public var guidance: AccessibilityGuidance {
        switch trusted {
        case true?: .trusted
        case false?: .stale
        case nil: .untrusted
        }
    }

    public mutating func checked(trusted: Bool) {
        self.trusted = trusted
    }
}
