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
    private lazy var unreachableRetry = UnreachableReadRetry { [weak self] in self?.check() }

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.check() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)
            .compactMap { $0.userInfo?[AccessibilityReading.notificationKey] as? AccessibilityReading }
            .receive(on: RunLoop.main)
            .sink { [weak self] reading in self?.land(reading) }
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

    private func log(_ read: AccessibilityRead) {
        let guidance = trust.guidance.rawValue
        if read == .unreachable {
            Self.log.error("Accessibility trust read failed because the XPC helper didn't answer, HUD settings show \(guidance, privacy: .public)")
        } else {
            Self.log.notice("Accessibility trust read \(read.rawValue, privacy: .public), HUD settings show \(guidance, privacy: .public)")
        }
    }

    var isSettled: Bool { checksInFlight == 0 }

    private func land(_ reading: AccessibilityReading) {
        guard trust.checked(reading) else { return }
        unreachableRetry.landed(reading.read)
    }

    @discardableResult
    func check() -> Task<AccessibilityRead, Never> {
        checksInFlight += 1
        return Task { @MainActor in
            let reading = await XPCHelperClient.shared.readAccessibilityTrust()
            land(reading)
            log(reading.read)
            checksInFlight -= 1
            return trust.lastRead ?? reading.read
        }
    }
}
