import Combine

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published var pane = "General"
}
