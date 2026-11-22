//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit
import OSLog
import T3IsleCore

@MainActor
enum ApplicationRelauncher {
    private static let log = Logger(subsystem: bundleIdentifier, category: "relaunch")
    private static var isRelaunching = false

    private struct AlreadyRelaunching: LocalizedError {
        var errorDescription: String? { "a relaunch is already in progress" }
    }

    static func restart(demo: Bool, onFailure: @escaping @MainActor (Error) -> Void = { _ in }) {
        guard !isRelaunching else { return onFailure(AlreadyRelaunching()) }
        isRelaunching = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = launchArguments(demo: demo)

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    isRelaunching = false
                    log.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
                    return onFailure(error)
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static func launchArguments(demo: Bool) -> [String] {
        StateFolders.current.launchArguments + (demo ? ["--demo"] : [])
    }
}
