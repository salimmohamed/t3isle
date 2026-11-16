#if DEBUG
import Foundation

public enum DebugTab: String, CaseIterable, Sendable {
    case home, shelf, t3
}

public enum DebugCommand: Equatable, Sendable {
    case openSettings(pane: String?)
    case openNotch
    case closeNotch
    case tab(DebugTab)
    case demo(Bool)
    case question
    case planDone
    case airpodsConnect(name: String, battery: Int?)
    case airpodsDisconnect

    public static let scheme = "t3isle-debug"
    public static let launchFlag = "--debug"

    public struct Spec: Sendable {
        public let name: String
        public let arguments: String
        public let summary: String
        let build: @Sendable ([String]) -> DebugCommand?

        public var usage: String { arguments.isEmpty ? name : "\(name) \(arguments)" }
    }

    public static let specs: [Spec] = [
        Spec(name: "open-settings", arguments: "[pane]", summary: "Open Settings, optionally on a pane such as t3 or appearance") {
            $0.count <= 1 ? .openSettings(pane: $0.first) : nil
        },
        Spec(name: "open-notch", arguments: "", summary: "Open the notch and keep it open") { $0.isEmpty ? .openNotch : nil },
        Spec(name: "close-notch", arguments: "", summary: "Close the notch") { $0.isEmpty ? .closeNotch : nil },
        Spec(name: "tab", arguments: "home|shelf|t3", summary: "Open the notch on a tab") {
            $0.count == 1 ? DebugTab(rawValue: $0[0].lowercased()).map(DebugCommand.tab) : nil
        },
        Spec(name: "demo", arguments: "on|off", summary: "Relaunch with or without demo data") {
            switch $0 {
            case ["on"]: .demo(true)
            case ["off"]: .demo(false)
            default: nil
            }
        },
        Spec(name: "question", arguments: "", summary: "Add a fake T3 thread that asks a question") { $0.isEmpty ? .question : nil },
        Spec(name: "plan-done", arguments: "", summary: "Add a fake T3 thread that finishes its plan, which shows the banner") {
            $0.isEmpty ? .planDone : nil
        },
        Spec(name: "airpods-connect", arguments: "[name] [battery]", summary: "Show the headphones activity as if they just connected",
             build: airpodsConnect),
        Spec(name: "airpods-disconnect", arguments: "", summary: "Hide the headphones activity") { $0.isEmpty ? .airpodsDisconnect : nil },
    ]

    private static func airpodsConnect(_ arguments: [String]) -> DebugCommand? {
        switch arguments.count {
        case 0: return .airpodsConnect(name: "AirPods Pro", battery: nil)
        case 1: return .airpodsConnect(name: arguments[0], battery: nil)
        case 2:
            guard let battery = Int(arguments[1]), (0...100).contains(battery) else { return nil }
            return .airpodsConnect(name: arguments[0], battery: battery)
        default: return nil
        }
    }

    public static func parse(_ tokens: [String]) throws -> DebugCommand {
        guard let name = tokens.first else { throw DebugCommandError.empty }
        guard let spec = specs.first(where: { $0.name == name.lowercased() }) else {
            throw DebugCommandError.unknown(name)
        }
        guard let command = spec.build(Array(tokens.dropFirst())) else { throw DebugCommandError.usage(spec.usage) }
        return command
    }

    public static func parse(url: URL) throws -> DebugCommand {
        guard url.scheme?.lowercased() == scheme else { throw DebugCommandError.notDebugURL(url.absoluteString) }
        let host = url.host(percentEncoded: false).map { [$0] } ?? []
        let path = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        return try parse((host + path).filter { !$0.isEmpty })
    }

    public static func launchCommands(_ arguments: [String]) throws -> [DebugCommand] {
        var groups: [[String]] = []
        var collecting = false
        for argument in arguments {
            if argument == launchFlag {
                groups.append([])
                collecting = true
            } else if argument.hasPrefix("-") {
                collecting = false
            } else if collecting {
                groups[groups.count - 1].append(argument)
            }
        }
        return try groups.map(parse)
    }
}

public enum DebugCommandError: Error, Equatable, LocalizedError {
    case empty
    case unknown(String)
    case usage(String)
    case notDebugURL(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "No debug command given"
        case .unknown(let name): "Unknown debug command \"\(name)\""
        case .usage(let usage): "Usage: \(usage)"
        case .notDebugURL(let url): "Not a \(DebugCommand.scheme) URL: \(url)"
        }
    }
}
#endif
