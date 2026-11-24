import AppKit
import Combine
import Defaults
import T3IsleCore

@MainActor
final class HUDAccessibility: ObservableObject {
    static let shared = HUDAccessibility()

    @Published private(set) var trust = AccessibilityTrust(asked: Defaults[.hudAccessibilityRequested])
    private var checksInFlight = 0
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.appBecameActive() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
            .compactMap { $0.userInfo?["granted"] as? Bool }
            .receive(on: RunLoop.main)
            .sink { [weak self] granted in self?.update { $0.checked(trusted: granted) } }
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
        update { $0.requested() }
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    #if DEBUG
    func requestWithoutPrompt() {
        update { $0.requested() }
    }

    func forgetRequest() {
        update { $0.forgetRequest() }
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
            update { apply(&$0, trusted) }
            checksInFlight -= 1
        }
    }

    private func update(_ change: (inout AccessibilityTrust) -> Void) {
        change(&trust)
        Defaults[.hudAccessibilityRequested] = trust.asked
    }
}
