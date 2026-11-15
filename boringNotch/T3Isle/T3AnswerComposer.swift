import AppKit
import SwiftUI
import T3IsleCore

@MainActor
final class T3AnswerComposer {
    static let shared = T3AnswerComposer()

    private var panel: ComposerPanel?

    func present(prompt: PendingPrompt, submit: @escaping (String) -> Void) {
        close()
        let panel = ComposerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .mainMenu + 4
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ComposerView(prompt: prompt, submit: { [weak self] text in
            submit(text)
            self?.close()
        }, cancel: { [weak self] in self?.close() }))
        if let screen = NSScreen.main {
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 210, y: frame.maxY - T3Tabs.openSize.height - 170))
        }
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ComposerView: View {
    let prompt: PendingPrompt
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.threadTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(prompt.detail ?? prompt.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
            TextField("Your answer", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($focused)
                .onSubmit(send)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Send", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func send() {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        submit(answer)
    }
}
