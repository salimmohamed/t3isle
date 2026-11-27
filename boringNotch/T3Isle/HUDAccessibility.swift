import AppKit
import Combine
import OSLog
import T3IsleCore

@MainActor
final class HUDAccessibility: ObservableObject {
    static let shared = HUDAccessibility()
    private static let log = Logger(subsystem: bundleIdentifier, category: "accessibility")

    @Published private(set) var trust = AccessibilityTrust()
    private var checksInFlight = 0
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.appBecameActive() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
            .compactMap { $0.userInfo?["granted"] as? Bool }
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in self?.trust.checked(trusted: granted) }
            .store(in: &cancellables)
    }

    var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "T3 Isle"
    }

    func paneAppeared() {
        check { trust, trusted in trust.checked(trusted: trusted) }
    }

    func appBecameActive() {
        check { trust, trusted in trust.appBecameActive(trusted: trusted) }
    }

    func request() {
        trust.requested()
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    #if DEBUG
    func requestWithoutPrompt() {
        trust.requested()
    }
    #endif

    func openSystemSettings() {
        guard let url = URL(string: AccessibilityTrust.settingsAddress) else { return }
        NSWorkspace.shared.open(url)
    }

    var isSettled: Bool { checksInFlight == 0 }

    private func check(_ apply: @escaping (inout AccessibilityTrust, Bool) -> Void) {
        checksInFlight += 1
        Task { @MainActor in
            let trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            apply(&trust, trusted)
            Self.log.notice("Accessibility trust read \(trusted ? "trusted" : "untrusted", privacy: .public), HUD settings show \(self.trust.guidance.rawValue, privacy: .public)")
            checksInFlight -= 1
        }
    }
}
