import AppKit
import Defaults
import SwiftUI
import T3IsleCore

final class SystemPasteboard: ClipboardSource {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    var types: [String] { pasteboard.types?.map(\.rawValue) ?? [] }

    func string() -> String? { pasteboard.string(forType: .string) }

    func setString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

struct ClipboardHistoryColumn: View {
    @ObservedObject private var history = T3IsleRuntime.shared.clipboard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Copied", systemImage: "doc.on.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(T3Theme.secondary)
            if history.items.isEmpty {
                Text("Text you copy shows up here")
                    .font(.system(size: 11))
                    .foregroundStyle(T3Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(history.items, id: \.self) { text in
                            ClipboardHistoryRow(text: text) { history.copy(text) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(8)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .animation(.smooth(duration: 0.2), value: history.items)
    }
}

private struct ClipboardHistoryRow: View {
    let text: String
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: copy) {
            Text(ClipboardHistory.preview(text))
                .font(.system(size: 12))
                .foregroundStyle(T3Theme.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy")
    }
}

struct ClipboardHistorySettings: View {
    @Default(.boringShelf) private var shelfEnabled

    var body: some View {
        Section {
            Defaults.Toggle(key: .clipboardHistory) { Text("Show clipboard history") }
                .disabled(!shelfEnabled)
        } header: {
            Text("Clipboard history")
        } footer: {
            Text(shelfEnabled
                 ? "Shows your last 20 text copies in the Shelf tab. Click one to copy it again. The list stays in memory only, and copies that password managers mark as concealed are skipped."
                 : "Turn on the shelf to use clipboard history.")
                .foregroundStyle(.secondary)
        }
    }
}
