import SwiftUI
import T3IsleCore

struct T3QuestionCarousel: View {
    @ObservedObject var model: T3IsleModel
    @State private var forward = true

    var body: some View {
        let prompts = model.prompts
        VStack(alignment: .leading, spacing: 6) {
            if let prompt = prompts.first {
                HStack(spacing: 6) {
                    Image(systemName: prompt.isApproval ? "hand.raised.fill" : "questionmark.bubble.fill")
                        .foregroundStyle(T3Theme.attention)
                    Text(prompt.threadTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3Theme.primary)
                        .lineLimit(1)
                    if !prompt.project.isEmpty {
                        Text(prompt.project)
                            .font(.system(size: 10))
                            .foregroundStyle(T3Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    PageDots(count: prompts.count)
                    Text("1 of \(prompts.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(T3Theme.attention)
                        .contentTransition(.numericText())
                }
                ZStack(alignment: .topLeading) {
                    PromptCard(prompt: prompt, model: model)
                        .id(prompt.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(T3Theme.attention.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(T3Theme.attention.opacity(0.55), lineWidth: 1))
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: prompts.map(\.id))
    }
}

private struct PageDots: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 5), id: \.self) { index in
                Capsule()
                    .fill(index == 0 ? T3Theme.attention : Color.white.opacity(0.25))
                    .frame(width: index == 0 ? 10 : 4, height: 4)
            }
        }
    }
}

private struct PromptCard: View {
    let prompt: PendingPrompt
    @ObservedObject var model: T3IsleModel
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(prompt.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(T3Theme.primary)
                if case .question(_, let index, let count) = prompt.kind, count > 1 {
                    Text("Question \(index + 1) of \(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(T3Theme.muted)
                }
            }
            if let detail = prompt.detail {
                Text(detail)
                    .font(prompt.isApproval && prompt.requestKind == "command"
                          ? .system(size: 11, design: .monospaced) : .system(size: 11.5))
                    .foregroundStyle(T3Theme.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch prompt.kind {
        case .approval(let choices):
            HStack(spacing: 6) {
                ForEach(choices, id: \.self) { choice in
                    let decision = ApprovalDecision(rawValue: choice.decision) ?? .accept
                    PromptButton(title: choice.label, style: style(for: decision)) {
                        model.respond(prompt, decision: decision)
                    }
                }
                Spacer(minLength: 0)
                InterruptLink(threadId: prompt.threadId, model: model)
            }
        case .question(let question, _, _):
            FlowRow(spacing: 6) {
                ForEach(question.options, id: \.self) { option in
                    PromptButton(title: option.label, style: question.multiSelect == true && selected.contains(option.answerValue)
                                 ? .primary : .secondary, help: option.description) {
                        if question.multiSelect == true {
                            if selected.contains(option.answerValue) { selected.remove(option.answerValue) } else { selected.insert(option.answerValue) }
                        } else {
                            model.answer(prompt, with: .text(option.answerValue))
                        }
                    }
                }
                if question.multiSelect == true {
                    PromptButton(title: "Submit", style: .primary) {
                        model.answer(prompt, with: .choices(question.options.map(\.answerValue).filter(selected.contains)))
                    }
                    .disabled(selected.isEmpty)
                }
                if question.allowsFreeText {
                    PromptButton(title: question.options.isEmpty ? "Type an answer…" : "Other…",
                                 style: question.options.isEmpty ? .primary : .ghost) {
                        T3AnswerComposer.shared.present(prompt: prompt) { text in
                            model.answer(prompt, with: .text(text))
                        }
                    }
                }
            }
        }
    }

    private func style(for decision: ApprovalDecision) -> PromptButton.Style {
        switch decision {
        case .accept: .primary
        case .decline, .cancel: .destructive
        case .acceptForSession, .acceptAlways: .secondary
        }
    }
}

struct InterruptLink: View {
    let threadId: String
    @ObservedObject var model: T3IsleModel

    var body: some View {
        PromptButton(title: "Interrupt", style: .ghost, icon: "stop.fill") {
            model.interrupt(threadId)
        }
        .help("Stop the agent's current turn")
    }
}

struct PromptButton: View {
    enum Style { case primary, secondary, destructive, ghost }

    let title: String
    var style: Style = .secondary
    var icon: String?
    var help: String?
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 8, weight: .bold)) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScale())
        .help(help ?? title)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    }

    private var foreground: Color {
        switch style {
        case .primary: .black
        case .destructive: T3Theme.failed
        case .secondary: T3Theme.primary
        case .ghost: hovered ? T3Theme.primary : T3Theme.secondary
        }
    }

    private var background: Color {
        switch style {
        case .primary: T3Theme.attention.opacity(hovered ? 1 : 0.9)
        case .destructive: T3Theme.failed.opacity(hovered ? 0.24 : 0.14)
        case .secondary: Color.white.opacity(hovered ? 0.18 : 0.1)
        case .ghost: Color.white.opacity(hovered ? 0.1 : 0)
        }
    }
}

struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let limit = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > limit {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
