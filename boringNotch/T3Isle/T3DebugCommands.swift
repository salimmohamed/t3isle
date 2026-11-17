#if DEBUG
import AppKit
import Defaults
import OSLog
import T3IsleCore

@MainActor
enum T3DebugCommands {
    private static let log = Logger(subsystem: bundleIdentifier, category: "debug-command")
    private static let settingsPanes = ["General", "T3", "Appearance", "Media", "Calendar", "HUD", "Battery", "Shelf",
                                        "Shortcuts", "Advanced", "About"]

    static func run(launchArguments arguments: [String], notch: @escaping @MainActor () -> BoringViewModel) {
        let commands: [DebugCommand]
        do {
            commands = try DebugCommand.launchCommands(arguments)
        } catch {
            return report(arguments.joined(separator: " "), error)
        }
        guard !commands.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            for command in commands { run(command, notch: notch()) }
        }
    }

    static func run(url: URL, notch: BoringViewModel) {
        do {
            run(try DebugCommand.parse(url: url), notch: notch)
        } catch {
            report(url.absoluteString, error)
        }
    }

    static func run(_ command: DebugCommand, notch: BoringViewModel) {
        let runtime = T3IsleRuntime.shared
        switch command {
        case .openSettings(let pane):
            if let pane {
                guard let match = settingsPanes.first(where: { $0.caseInsensitiveCompare(pane) == .orderedSame }) else {
                    return report("open-settings \(pane)", "Unknown pane. Panes: \(settingsPanes.joined(separator: ", "))")
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
            if on != T3IsleRuntime.isDemo { relaunch(arguments: on ? ["--demo"] : []) }
        case .replay(let name):
            guard Defaults[.t3Enabled] else { return report(command.line, "T3 is turned off in Settings") }
            do {
                runtime.play(try Scenario.named(name))
            } catch {
                return report(command.line, error)
            }
        case .replayOff:
            guard Defaults[.t3Enabled] else { return report(command.line, "T3 is turned off in Settings") }
            runtime.stopReplay()
        case .airpodsConnect(let name, let battery):
            runtime.showHeadphones(name: name, battery: battery)
        case .airpodsDisconnect:
            runtime.hideHeadphones()
        }
        log.notice("ran \(command.line, privacy: .public)")
    }

    private static func relaunch(arguments: [String]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error { return report("relaunch", error) }
                NSApp.terminate(nil)
            }
        }
    }

    private static func report(_ input: String, _ error: Error) {
        report(input, error.localizedDescription)
    }

    private static func report(_ input: String, _ message: String) {
        log.error("failed \(input, privacy: .public): \(message, privacy: .public)")
    }
}
#endif
