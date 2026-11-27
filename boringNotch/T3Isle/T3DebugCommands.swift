#if DEBUG
import AppKit
import Defaults
import T3IsleCore

@MainActor
enum T3DebugCommands {
    private struct Failure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    private static let settingsPanes = ["General", "T3", "Appearance", "Media", "Calendar", "HUD", "Battery", "Shelf",
                                        "Shortcuts", "Advanced", "About"]
    private static var monitor: T3DebugMonitor { .shared }

    static func run(launchArguments arguments: [String], notch: @escaping @MainActor () -> BoringViewModel) {
        let commands: [DebugCommand]
        do {
            commands = try DebugCommand.launchCommands(arguments)
        } catch {
            return failed(arguments.joined(separator: " "), error)
        }
        guard !commands.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for command in commands { run(command, input: "\(DebugCommand.launchFlag) \(command.line)", notch: notch()) }
        }
    }

    static func run(url: URL, notch: BoringViewModel) {
        do {
            run(try DebugCommand.parse(url: url), input: url.absoluteString, notch: notch)
        } catch {
            failed(url.absoluteString, error)
        }
    }

    private static func run(_ command: DebugCommand, input: String, notch: BoringViewModel) {
        do {
            try perform(command, notch: notch)
            var attributes = ["input": input, "command": command.line]
            attributes["reverse"] = command.reverse?.line
            monitor.record("command.ran", attributes)
        } catch {
            failed(input, error)
        }
    }

    private static func perform(_ command: DebugCommand, notch: BoringViewModel) throws {
        let runtime = T3IsleRuntime.shared
        switch command {
        case .openSettings(let pane):
            if let pane {
                guard let match = settingsPanes.first(where: { $0.caseInsensitiveCompare(pane) == .orderedSame }) else {
                    throw Failure("Unknown pane. Panes: \(settingsPanes.joined(separator: ", "))")
                }
                SettingsNavigation.shared.pane = match
            }
            SettingsWindowController.shared.showWindow()
        case .closeSettings:
            SettingsWindowController.shared.close()
        case .openNotch:
            notch.open()
        case .closeNotch:
            notch.close()
        case .tab(let tab):
            BoringViewCoordinator.shared.currentView = tab
            notch.open()
        case .demo(let on):
            if on != T3IsleRuntime.isDemo {
                ApplicationRelauncher.restart(demo: on) { failed("relaunch", $0) }
            }
        case .replay(let name):
            try requireT3()
            runtime.play(try Scenario.named(name))
        case .replayOff:
            try requireT3()
            runtime.stopReplay()
        case .state:
            monitor.writeStateWhenSettled(notch: notch)
        case .airpodsConnect(let name, let battery, let device):
            guard Defaults[.t3HeadphonesActivity] else { throw Failure("The headphones pop-up is turned off in Settings") }
            runtime.showHeadphones(name: name, battery: battery, device: device)
        case .airpodsDisconnect:
            runtime.hideHeadphones()
        case .bluetoothAccess(let access):
            let system = runtime.systemBluetoothAccess
            guard access != .allowed || system == .allowed else {
                throw Failure("Bluetooth access for this app is \(system.rawValue), so allowed would call Bluetooth without access")
            }
            runtime.feedBluetoothAccess(access)
        case .accessibilityTrust(let read):
            XPCHelperClient.shared.overrideTrust(read)
            HUDAccessibility.shared.hudSwitch.check()
        case .pomodoro(let action):
            guard Defaults[.pomodoroTimer] else { throw Failure("The Pomodoro timer is turned off in Settings") }
            switch action {
            case .start: runtime.pomodoro.start()
            case .pause: runtime.pomodoro.pause()
            case .reset: runtime.pomodoro.reset()
            }
        }
    }

    private static func requireT3() throws {
        guard Defaults[.t3Enabled] else { throw Failure("T3 is turned off in Settings") }
    }

    private static func failed(_ input: String, _ error: Error) {
        monitor.record("command.failed", ["input": input, "message": error.localizedDescription])
    }
}
#endif
