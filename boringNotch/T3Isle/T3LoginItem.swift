import AppKit
import OSLog
import ServiceManagement
import SwiftUI
import T3IsleCore

@MainActor
enum T3LoginItem {
    private static let log = Logger(subsystem: bundleIdentifier, category: "login-item")

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var plan: LoginItemPlan {
        LoginItemPlan(isDebug: isDebugBuild, status: LoginItemStatus(SMAppService.mainApp.status))
    }

    static func refreshAtLaunch() {
        apply(plan.atLaunch, reason: "launch")
    }

    static func set(_ on: Bool) {
        apply(plan.toggled(on: on), reason: on ? "switched on" : "switched off")
    }

    private static func apply(_ action: LoginItemAction, reason: String) {
        do {
            switch action {
            case .none: break
            case .register: try SMAppService.mainApp.register()
            case .unregister: try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("\(reason, privacy: .public): \(action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        let status = plan.status.rawValue
        let path = Bundle.main.bundlePath
        log.notice("\(reason, privacy: .public): \(action.rawValue, privacy: .public), status \(status, privacy: .public), app \(path, privacy: .public)")
    }
}

private extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        default: self = .notRegistered
        }
    }
}

struct T3LaunchAtLoginToggle: View {
    @State private var plan = T3LoginItem.plan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at login", isOn: Binding(
                get: { plan.isOn },
                set: { on in
                    T3LoginItem.set(on)
                    plan = T3LoginItem.plan
                }
            ))
            .disabled(plan.isDebug)
            if let note = plan.note {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if note != .unavailableInDebug {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }
        .onAppear { plan = T3LoginItem.plan }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            plan = T3LoginItem.plan
        }
    }
}
