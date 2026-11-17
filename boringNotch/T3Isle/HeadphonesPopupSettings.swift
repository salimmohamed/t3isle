import Defaults
import SwiftUI

struct HeadphonesPopupSettings: View {
    var body: some View {
        Section {
            Defaults.Toggle(key: .t3HeadphonesActivity) { Text("Show a pop-up when headphones connect") }
        } header: {
            Text("Headphones")
        } footer: {
            Text("Shows the headphones and their battery level in the closed notch for a few seconds. Your Mac's own battery is under Battery.")
                .foregroundStyle(.secondary)
        }
    }
}
