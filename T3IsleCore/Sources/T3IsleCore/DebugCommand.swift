#if DEBUG
import Foundation

public enum DebugCommand: Equatable, Sendable {
    case openSettings(pane: String?)
    case closeSettings
    case openNotch
    case closeNotch
    case tab(NotchTab)
    case demo(Bool)
    case replay(String)
    case replayOff
    case state
    case airpodsConnect(name: String, battery: Int?, device: BluetoothAudioClass?)
    case airpodsDisconnect
    case bluetoothAccess(BluetoothAccess?)
    case accessibilityTrust(Bool?)

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
        Spec(name: "close-settings", arguments: "", summary: "Close Settings") { $0.isEmpty ? .closeSettings : nil },
        Spec(name: "open-notch", arguments: "", summary: "Open the notch and keep it open") { $0.isEmpty ? .openNotch : nil },
        Spec(name: "close-notch", arguments: "", summary: "Close the notch") { $0.isEmpty ? .closeNotch : nil },
        Spec(name: "tab", arguments: "home|t3|shelf", summary: "Open the notch on a tab") {
            $0.count == 1 ? NotchTab(rawValue: $0[0].lowercased()).map(DebugCommand.tab) : nil
        },
        Spec(name: "demo", arguments: "on|off", summary: "Relaunch with or without demo data") {
            switch $0 {
            case ["on"]: .demo(true)
            case ["off"]: .demo(false)
            default: nil
            }
        },
        Spec(name: "replay", arguments: (Scenario.names + ["off"]).joined(separator: "|"),
             summary: "Replay a recorded T3 scenario in place of the real one, or go back to it with off", build: replay),
        Spec(name: "state", arguments: "", summary: "Write what the app shows as JSON to the state file") { $0.isEmpty ? .state : nil },
        Spec(name: "airpods-connect", arguments: "[name] [battery] [\(BluetoothAudioClass.allCases.map(\.rawValue).joined(separator: "|"))]",
             summary: "Show the headphones activity as if a device of that Bluetooth class just connected", build: airpodsConnect),
        Spec(name: "airpods-disconnect", arguments: "", summary: "Hide the headphones activity") { $0.isEmpty ? .airpodsDisconnect : nil },
        Spec(name: "bluetooth-access", arguments: (BluetoothAccess.allCases.map(\.rawValue) + ["system"]).joined(separator: "|"),
             summary: "Feed the headphones monitor a Bluetooth access change, or the real access again with system", build: bluetoothAccess),
        Spec(name: "accessibility-trust", arguments: "trusted|untrusted|system",
             summary: "Override the Accessibility trust the app reads and re-check it as if you came back to the app",
             build: accessibilityTrust),
    ]

    public var tokens: [String] {
        switch self {
        case .openSettings(let pane): ["open-settings"] + (pane.map { [$0] } ?? [])
        case .closeSettings: ["close-settings"]
        case .openNotch: ["open-notch"]
        case .closeNotch: ["close-notch"]
        case .tab(let tab): ["tab", tab.rawValue]
        case .demo(let on): ["demo", on ? "on" : "off"]
        case .replay(let scenario): ["replay", scenario]
        case .replayOff: ["replay", "off"]
        case .state: ["state"]
        case .airpodsConnect(let name, let battery, let device):
            ["airpods-connect", name] + (battery.map { [String($0)] } ?? []) + (device.map { [$0.rawValue] } ?? [])
        case .airpodsDisconnect: ["airpods-disconnect"]
        case .bluetoothAccess(let access): ["bluetooth-access", access?.rawValue ?? "system"]
        case .accessibilityTrust(let trusted): ["accessibility-trust", trusted.map { $0 ? "trusted" : "untrusted" } ?? "system"]
        }
    }

    public var line: String { tokens.joined(separator: " ") }

    public var reverse: DebugCommand? {
        switch self {
        case .openSettings: .closeSettings
        case .closeSettings: .openSettings(pane: nil)
        case .openNotch, .tab: .closeNotch
        case .closeNotch: .openNotch
        case .demo(let on): .demo(!on)
        case .replay, .replayOff: .replayOff
        case .state: nil
        case .airpodsConnect: .airpodsDisconnect
        case .airpodsDisconnect: .airpodsConnect(name: "AirPods Pro", battery: nil, device: nil)
        case .bluetoothAccess: .bluetoothAccess(nil)
        case .accessibilityTrust: .accessibilityTrust(nil)
        }
    }

    private static func replay(_ arguments: [String]) -> DebugCommand? {
        guard arguments.count == 1 else { return nil }
        let name = arguments[0].lowercased()
        if name == "off" { return .replayOff }
        return Scenario.names.contains(name) ? .replay(name) : nil
    }

    private static func bluetoothAccess(_ arguments: [String]) -> DebugCommand? {
        guard arguments.count == 1 else { return nil }
        let name = arguments[0].lowercased()
        if name == "system" { return .bluetoothAccess(nil) }
        return BluetoothAccess(rawValue: name).map(DebugCommand.bluetoothAccess)
    }

    private static func accessibilityTrust(_ arguments: [String]) -> DebugCommand? {
        switch arguments.map({ $0.lowercased() }) {
        case ["trusted"]: .accessibilityTrust(true)
        case ["untrusted"]: .accessibilityTrust(false)
        case ["system"]: .accessibilityTrust(nil)
        default: nil
        }
    }

    private static func airpodsConnect(_ arguments: [String]) -> DebugCommand? {
        guard let name = arguments.first else { return .airpodsConnect(name: "AirPods Pro", battery: nil, device: nil) }
        var rest = arguments.dropFirst()
        var battery: Int?
        if let first = rest.first, let level = Int(first) {
            guard (0...100).contains(level) else { return nil }
            battery = level
            rest = rest.dropFirst()
        }
        var device: BluetoothAudioClass?
        if let first = rest.first {
            guard let named = BluetoothAudioClass(rawValue: first.lowercased()) else { return nil }
            device = named
            rest = rest.dropFirst()
        }
        return rest.isEmpty ? .airpodsConnect(name: name, battery: battery, device: device) : nil
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
