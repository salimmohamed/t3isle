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
            if on != T3IsleRuntime.isDemo { relaunch(arguments: StateFolders.current.launchArguments + (on ? ["--demo"] : [])) }
        case .replay(let name):
            try requireT3()
            runtime.play(try Scenario.named(name))
        case .replayOff:
            try requireT3()
            runtime.stopReplay()
        case .state:
            monitor.writeStateWhenSettled(notch: notch)
        case .airpodsConnect(let name, let battery):
            runtime.showHeadphones(name: name, battery: battery)
        case .airpodsDisconnect:
            runtime.hideHeadphones()
        }
    }

    private static func requireT3() throws {
        guard Defaults[.t3Enabled] else { throw Failure("T3 is turned off in Settings") }
    }

    private static func relaunch(arguments: [String]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error { return failed("relaunch", error) }
                NSApp.terminate(nil)
            }
        }
    }

    private static func failed(_ input: String, _ error: Error) {
        monitor.record("command.failed", ["input": input, "message": error.localizedDescription])
    }
}
#endif
