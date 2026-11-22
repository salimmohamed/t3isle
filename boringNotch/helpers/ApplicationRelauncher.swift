//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit
import T3IsleCore

enum ApplicationRelauncher {
    static func restart(adding extraArguments: [String] = [], onFailure: @escaping @MainActor (Error) -> Void = { _ in }) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = launchArguments + extraArguments

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error { return onFailure(error) }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static var launchArguments: [String] {
        #if DEBUG
        StateFolders.current.launchArguments
        #else
        []
        #endif
    }
}
