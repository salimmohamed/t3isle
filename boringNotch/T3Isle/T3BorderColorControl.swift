import AppKit
import Defaults
import SwiftUI
import T3IsleCore

@MainActor
final class T3BorderPreview: ObservableObject {
    static let shared = T3BorderPreview()

    @Published var popoverOpen = false
    @Published fileprivate var panelOpen = false

    var isActive: Bool { popoverOpen || panelOpen }
}

@MainActor
private final class T3CustomBorderColor: NSObject {
    static let shared = T3CustomBorderColor()

    private var visibility: NSKeyValueObservation?

    func open() {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.showsAlpha = false
        panel.color = NSColor(Color(hex: Defaults[.t3AttentionBorderHex]))
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        T3BorderPreview.shared.panelOpen = true
        visibility = panel.observe(\.isVisible) { panel, _ in
            DispatchQueue.main.async { Self.shared.panelVisibilityChanged(panel) }
        }
    }

    private func panelVisibilityChanged(_ panel: NSColorPanel) {
        guard !panel.isVisible, visibility != nil else { return }
        visibility = nil
        panel.setTarget(nil)
        T3BorderPreview.shared.panelOpen = false
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
        Defaults[.t3AttentionBorderHex] = channels.reduce("#") { $0 + String(format: "%02X", $1) }
    }
}

struct T3BorderColorControl: View {
    @Default(.t3AttentionBorderHex) private var hex
    @Environment(\.isEnabled) private var isEnabled
    @State private var showingPalette = false

    var body: some View {
        Button { showingPalette.toggle() } label: {
            T3Swatch(color: Color(hex: hex), selected: false, size: 18)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .help("Attention border color")
        .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
            T3BorderPalette(hex: $hex)
        }
        .onChange(of: showingPalette) { _, open in T3BorderPreview.shared.popoverOpen = open }
        .onDisappear { T3BorderPreview.shared.popoverOpen = false }
    }
}

private struct T3BorderPalette: View {
    @Binding var hex: String
    @State private var hovered: BorderSwatch?

    private var choice: BorderChoice { BorderPalette.choice(forHex: hex) }

    private var caption: String {
        if let hovered { return hovered.label }
        switch choice {
        case .standard: return "T3 orange"
        case .preset(let swatch): return swatch.label
        case .custom(let custom): return "Custom \(custom)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .custom(let custom) = choice {
                namedRow("Custom \(custom)", hex: custom, selected: true)
            }
            namedRow("T3 orange (default)", hex: BorderPalette.standardHex, selected: choice == .standard)
            ForEach(BorderPalette.themes) { theme in
                HStack(spacing: 8) {
                    Text(theme.title).frame(width: 128, alignment: .leading)
                    ForEach(theme.swatches) { swatch in
                        swatchButton(swatch, selected: choice == .preset(swatch))
                    }
                }
            }
            Divider()
            HStack {
                Button("Custom…") { T3CustomBorderColor.shared.open() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func namedRow(_ title: String, hex rowHex: String, selected: Bool) -> some View {
        Button { hex = rowHex } label: {
            HStack(spacing: 8) {
                T3Swatch(color: Color(hex: rowHex), selected: false, size: 16)
                Text(title)
                Spacer()
                Image(systemName: "checkmark").opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatchButton(_ swatch: BorderSwatch, selected: Bool) -> some View {
        Button { hex = swatch.hex } label: {
            T3Swatch(color: Color(hex: swatch.hex), selected: selected, size: 18)
        }
        .buttonStyle(PressScale())
        .onHover { inside in
            if inside { hovered = swatch } else if hovered == swatch { hovered = nil }
        }
        .accessibilityLabel(swatch.label)
    }
}

private struct T3Swatch: View {
    let color: Color
    let selected: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .padding(3)
            .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(selected ? 1 : 0))
            .frame(width: size + 6, height: size + 6)
    }
}
