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
            .sink { [weak self] _ in self?.check() }
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

    func request() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    func openSystemSettings() {
        guard let url = URL(string: AccessibilityTrust.settingsAddress) else { return }
        NSWorkspace.shared.open(url)
    }

    var isSettled: Bool { checksInFlight == 0 }

    func check() {
        checksInFlight += 1
        Task { @MainActor in
            let trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            trust.checked(trusted: trusted)
            Self.log.notice("Accessibility trust read \(trusted ? "trusted" : "untrusted", privacy: .public), HUD settings show \(self.trust.guidance.rawValue, privacy: .public)")
            checksInFlight -= 1
        }
    }
}
