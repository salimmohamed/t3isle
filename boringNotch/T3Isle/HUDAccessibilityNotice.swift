import SwiftUI
import T3IsleCore

struct HUDAccessibilityNotice: View {
    @ObservedObject var accessibility: HUDAccessibility

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accessibility.trust.guidance.showsReAddHint {
                Text("\(accessibility.appName) can't use Accessibility. Turn it on in Privacy & Security > Accessibility. If it's already on, the entry may be stale, so remove \(accessibility.appName) and add it again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accessibility Settings") { accessibility.openSystemSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Request Accessibility") { accessibility.request() }
                }
            } else {
                Text("Accessibility access is required to replace the system HUD.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Request Accessibility") { accessibility.request() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 6)
    }
}
