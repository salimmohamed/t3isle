import SwiftUI
import T3IsleCore

struct HUDAccessibilityNotice: View {
    let accessibility: HUDAccessibility

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accessibility.hudSwitch.guidance.showsReAddHint {
                Text("\(accessibility.appName) can't use Accessibility. Turn it on in Privacy & Security > Accessibility. If it's already on, the entry may be stale, so remove \(accessibility.appName) and add it again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accessibility Settings") { accessibility.openSystemSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Request Accessibility") { accessibility.request() }
                }
            } else if accessibility.hudSwitch.guidance.offersRequest {
                Text("Accessibility access is required to replace the system HUD.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Request Accessibility") { accessibility.request() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text("\(accessibility.appName) couldn't check Accessibility because its helper didn't answer. Replace system HUD stays as you left it until the helper answers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }
}
