import Foundation

public enum LoginItemStatus: String, Sendable {
    case notRegistered, enabled, requiresApproval, notFound
}

public enum LoginItemAction: String, Sendable {
    case none, register, unregister
}

public enum LoginItemNote: Equatable, Sendable {
    case unavailableInDebug
    case switchedOffInSettings
    case removeOtherEntries

    public var text: String {
        switch self {
        case .unavailableInDebug:
            "Debug builds never launch at login, so they can't replace the installed app's login item."
        case .switchedOffInSettings:
            "macOS has T3 Isle switched off in Login Items. Open Login Items, switch T3 Isle on, and remove any other T3 Isle entry there."
        case .removeOtherEntries:
            "If Login Items lists another T3 Isle, remove it so only this copy opens at login."
        }
    }
}

public struct LoginItemPlan: Sendable {
    public let isDebug: Bool
    public let status: LoginItemStatus

    public init(isDebug: Bool, status: LoginItemStatus) {
        self.isDebug = isDebug
        self.status = status
    }

    public var isOn: Bool {
        !isDebug && (status == .enabled || status == .requiresApproval)
    }

    public var atLaunch: LoginItemAction {
        switch status {
        case .enabled: isDebug ? .unregister : .register
        case .requiresApproval: isDebug ? .unregister : .none
        case .notRegistered, .notFound: .none
        }
    }

    public func toggled(on: Bool) -> LoginItemAction {
        guard !isDebug else { return .none }
        return on ? .register : .unregister
    }

    public var note: LoginItemNote? {
        if isDebug { return .unavailableInDebug }
        switch status {
        case .enabled: return .removeOtherEntries
        case .requiresApproval: return .switchedOffInSettings
        case .notRegistered, .notFound: return nil
        }
    }
}
