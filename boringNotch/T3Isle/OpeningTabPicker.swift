import Defaults
import SwiftUI
import T3IsleCore

struct OpeningTabPicker: View {
    @Default(.openingTab) private var openingTab

    var body: some View {
        Picker("Open notch on", selection: $openingTab) {
            ForEach(OpeningTab.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }
}
