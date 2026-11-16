import SwiftUI
import T3IsleCore

enum T3Theme {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let muted = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.08)
    static let card = Color.white.opacity(0.055)

    static let needsYou = Color(hex: "#FFB020")
    static let attention = Color(hex: BorderPalette.standardHex)
    static let working = Color(hex: "#3DD68C")
    static let replied = Color(hex: "#5AA9FF")
    static let failed = Color(hex: "#FF5D5D")

    static func mood(_ mood: ThreadMood) -> Color {
        switch mood {
        case .needsYou: needsYou
        case .working, .waiting: muted
        case .replied: replied
        case .failed: failed
        case .idle: primary
        }
    }

    static let shuffle = Animation.spring(response: 0.5, dampingFraction: 0.68)
    static let act = Animation.spring(response: 0.3, dampingFraction: 0.86)
    static let liveActivityIn = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let liveActivityOut = Animation.spring(response: 0.45, dampingFraction: 1.0)

    static func accent(_ provider: ProviderLimits) -> Color {
        if let hex = provider.accentHex { return Color(hex: hex) }
        return accent(providerId: provider.id)
    }

    static func accent(providerId: String) -> Color {
        switch providerId {
        case "claudeAgent", "claude": Color(hex: "#E8875B")
        case "codex": Color(hex: "#2563EB")
        default: secondary
        }
    }

    static func level(left: Double, warnAt: Int, criticalAt: Int) -> Color {
        left <= Double(criticalAt) ? failed : left <= Double(warnAt) ? needsYou : working
    }
}

extension Color {
    init(hex: String, greyscale: Bool = false) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0xFFFFFF
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        if greyscale {
            self.init(white: 0.2126 * red + 0.7152 * green + 0.0722 * blue)
        } else {
            self.init(red: red, green: green, blue: blue)
        }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    static var blurred: AnyTransition {
        .modifier(active: BlurModifier(radius: 3), identity: BlurModifier(radius: 0))
    }
}
