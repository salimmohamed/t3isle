import Foundation

public struct BorderSwatch: Hashable, Sendable, Identifiable {
    public let theme: String
    public let name: String
    public let hex: String

    public var id: String { hex }
    public var label: String { "\(theme) · \(name)" }
}

public struct BorderTheme: Hashable, Sendable, Identifiable {
    public let title: String
    public let swatches: [BorderSwatch]

    public var id: String { title }

    init(_ title: String, short: String, _ swatches: KeyValuePairs<String, String>) {
        self.title = title
        self.swatches = swatches.map { BorderSwatch(theme: short, name: $0.key, hex: BorderPalette.normalized($0.value)) }
    }
}

public enum BorderChoice: Equatable, Sendable {
    case standard
    case preset(BorderSwatch)
    case custom(hex: String)
}

public enum BorderPalette {
    public static let standardHex = "#FF8A1F"

    public static let themes: [BorderTheme] = [
        BorderTheme("Catppuccin Mocha", short: "Mocha", [
            "Peach": "#fab387", "Mauve": "#cba6f7", "Pink": "#f5c2e7", "Blue": "#89b4fa", "Green": "#a6e3a1",
        ]),
        BorderTheme("Tokyo Night", short: "Tokyo Night", [
            "Orange": "#ff9e64", "Purple": "#bb9af7", "Blue": "#7aa2f7", "Cyan": "#7dcfff", "Green": "#9ece6a",
        ]),
        BorderTheme("Rosé Pine", short: "Rosé Pine", [
            "Love": "#eb6f92", "Gold": "#f6c177", "Rose": "#ebbcba", "Iris": "#c4a7e7", "Foam": "#9ccfd8",
        ]),
        BorderTheme("Nord", short: "Nord", [
            "Orange": "#d08770", "Yellow": "#ebcb8b", "Green": "#a3be8c", "Purple": "#b48ead", "Frost": "#88c0d0",
        ]),
        BorderTheme("Gruvbox Dark", short: "Gruvbox", [
            "Orange": "#fe8019", "Yellow": "#fabd2f", "Aqua": "#8ec07c", "Red": "#fb4934", "Purple": "#d3869b",
        ]),
        BorderTheme("Dracula", short: "Dracula", [
            "Pink": "#ff79c6", "Purple": "#bd93f9", "Orange": "#ffb86c", "Green": "#50fa7b", "Cyan": "#8be9fd",
        ]),
    ]

    static func normalized(_ hex: String) -> String {
        "#" + hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
    }

    public static func choice(forHex hex: String) -> BorderChoice {
        let hex = normalized(hex)
        if hex == standardHex { return .standard }
        if let swatch = themes.lazy.flatMap(\.swatches).first(where: { $0.hex == hex }) { return .preset(swatch) }
        return .custom(hex: hex)
    }
}
