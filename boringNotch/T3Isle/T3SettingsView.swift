import Defaults
import SwiftUI
import T3IsleCore

struct T3SettingsView: View {
    @Default(.t3Enabled) private var enabled
    @Default(.t3AttentionBorder) private var borderShown
    @Default(.t3QuotaWindow) private var quotaWindow
    @Default(.t3QuotaWarnAt) private var warnAt
    @Default(.t3QuotaCriticalAt) private var criticalAt
    @Default(.t3FacesPerGroup) private var facesPerGroup

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .t3Enabled) { Text("Enable T3 Code integration") }
                if T3IsleRuntime.isDemo {
                    Text("Running with demo data (--demo).").foregroundStyle(.secondary)
                }
            } header: {
                Text("T3 Code")
            } footer: {
                Text("T3 Isle connects to T3 Code's server on this Mac and signs in with T3's command-line tool. The session token is kept in a private file only your account can read.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .t3OpenOnQuestion) { Text("Open the notch when an agent asks something") }
                Defaults.Toggle(key: .t3QuestionSound) { Text("Play a sound for new questions") }
                HStack {
                    Defaults.Toggle(key: .t3AttentionBorder) { Text("Show attention border around the notch") }
                    T3BorderColorControl().disabled(!borderShown)
                }
                Defaults.Toggle(key: .t3KeepFinishedPinned) { Text("Keep finished agents pinned as Done") }
                Defaults.Toggle(key: .t3ThreadActions) { Text("Snooze and settle threads from the notch") }
                Defaults.Toggle(key: .t3ShowSubagents) { Text("Show subagent threads") }
            } header: {
                Text("Behaviour")
            }
            .disabled(!enabled)

            Section {
                Picker("Quota window in the closed notch", selection: $quotaWindow) {
                    ForEach(QuotaWindowChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Defaults.Toggle(key: .t3ShowQuotaLeft) { Text("Show quota left instead of used") }
                Stepper("Warn at \(warnAt)% left", value: $warnAt, in: 5...90, step: 5)
                Stepper("Critical at \(criticalAt)% left", value: $criticalAt, in: 1...50, step: 1)
                Stepper("Faces per group: \(facesPerGroup)", value: $facesPerGroup, in: 1...6)
            } header: {
                Text("Limits and faces")
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .navigationTitle("T3 Code")
    }
}
