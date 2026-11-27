import AppKit
import Combine
import OSLog
import T3IsleCore

@MainActor
final class HUDAccessibility {
    static let shared = HUDAccessibility()
    private static let log = Logger(subsystem: bundleIdentifier, category: "accessibility")

    let hudSwitch: HUDReplacementSwitch
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        hudSwitch = HUDReplacementSwitch { await HUDAccessibility.read() }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.hudSwitch.check() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accessibilityTrustRead)
            .compactMap { $0.userInfo?[AccessibilityReading.notificationKey] as? AccessibilityReading }
            .receive(on: RunLoop.main)
            .sink { [weak self] reading in self?.hudSwitch.landed(reading) }
            .store(in: &cancellables)
    }

    var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "T3 Isle"
    }

    func request() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }

    func openSystemSettings() {
        guard let url = URL(string: HUDReplacementSwitch.settingsAddress) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func read() async -> AccessibilityReading {
        let reading = await XPCHelperClient.shared.readAccessibilityTrust()
        if reading.read == .unreachable {
            log.error("Accessibility trust read failed because the XPC helper didn't answer")
        } else {
            log.notice("Accessibility trust read \(reading.read.rawValue, privacy: .public)")
        }
        return reading
    }
}
