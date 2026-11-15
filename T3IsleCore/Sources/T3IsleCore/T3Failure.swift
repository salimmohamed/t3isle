import Foundation

public enum T3Failure: LocalizedError, Equatable {
    case notRunning
    case cliMissing
    case cliFailed(String)
    case signInRefused(String)
    case signedOut
    case actionsOff
    case http(Int, String?)
    case unreadable
    case rejected(String)
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "T3 Code isn't running."
        case .cliMissing: "T3's command-line tool is missing. Open T3 Code once to install it."
        case .cliFailed(let message): message
        case .signInRefused(let message): message
        case .signedOut: "T3 signed T3 Isle out."
        case .actionsOff: "Thread actions are off in Settings."
        case .http(let status, let message): message ?? "T3 answered with HTTP \(status)."
        case .unreadable: "T3 sent a reply T3 Isle couldn't read."
        case .rejected(let message): message
        case .keychain(let status): "Couldn't save the T3 sign-in (Keychain error \(status))."
        }
    }
}
