import SwiftUI
import T3IsleCore

struct T3AgentsColumn: View {
    @ObservedObject var model: T3IsleModel

    var body: some View {
        let selected = model.selectedCard
        VStack(alignment: .leading, spacing: 8) {
            if model.agentGroups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(T3Theme.muted)
                    Text("No agents running")
                        .font(.system(size: 11))
                        .foregroundStyle(T3Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ViewThatFits(in: .vertical) {
                    cardGroups(selected: selected)
                    ScrollView(.vertical, showsIndicators: false) {
                        cardGroups(selected: selected)
                    }
                    .frame(height: 96)
                }
                .frame(maxHeight: 96, alignment: .top)
                if let selected {
                    AgentDetailView(card: selected, detail: model.detail(for: selected.id),
                                    completed: model.completedSteps[selected.id] ?? [], model: model)
                        .id(selected.id)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.agentGroups)
    }

    private func cardGroups(selected: AgentCard?) -> some View {
        FlowRow(spacing: 8) {
            ForEach(model.agentGroups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(T3Theme.muted)
                        .lineLimit(1)
                    FlowRow(spacing: 6) {
                        ForEach(group.cards) { card in
                            AgentCardView(card: card, selected: card.id == selected?.id) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.select(card.id) }
                            } dismiss: {
                                model.dismissFinished(card.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentCardView: View {
    let card: AgentCard
    let selected: Bool
    let select: () -> Void
    let dismiss: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                BlobAvatar(seed: card.thread.id, mood: card.state == .done ? .replied : card.thread.mood, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.thread.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3Theme.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(stateColor).frame(width: 5, height: 5)
                        Text(stateText)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(stateColor)
                            .lineLimit(1)
                    }
                }
                .frame(width: 98, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.12) : hovered ? Color.white.opacity(0.07) : T3Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(card.state == .needsYou ? T3Theme.attention.opacity(0.7)
                                  : selected ? Color.white.opacity(0.2) : .clear, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if card.state == .done && hovered {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(T3Theme.secondary)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .offset(x: 4, y: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    }

    private var stateText: String {
        switch card.state {
        case .working: card.detail?.plan?.current?.text ?? "Working"
        case .needsYou: "Needs you"
        case .waiting: card.thread.status
        case .done: "Done"
        case .stopping: "Stopping…"
        }
    }

    private var stateColor: Color {
        switch card.state {
        case .working: T3Theme.working
        case .needsYou: T3Theme.attention
        case .waiting, .stopping: T3Theme.muted
        case .done: T3Theme.replied
        }
    }
}

struct AgentDetailView: View {
    let card: AgentCard
    let detail: AgentDetail?
    let completed: Set<String>
    @ObservedObject var model: T3IsleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if let plan = detail?.plan {
                        PlanChecklist(plan: plan, live: card.state != .done)
                    }
                    if let activity = detail?.activity, !activity.isEmpty {
                        ActivityFeed(entries: activity)
                    } else if detail == nil {
                        Text("Loading…").font(.system(size: 10.5)).foregroundStyle(T3Theme.muted)
                    } else if detail?.plan == nil, let line = card.thread.line {
                        Text(line).font(.system(size: 11)).foregroundStyle(T3Theme.secondary).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T3Theme.card))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProviderBadge(providerId: detail?.providerId ?? card.thread.providerId)
                Text(card.thread.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(T3Theme.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if card.state == .working || card.state == .needsYou || card.state == .waiting {
                    IconButton(icon: "stop.fill", help: "Interrupt the current turn") { model.interrupt(card.id) }
                }
                IconButton(icon: "arrow.up.right", help: "Open in T3 Code") { model.open(card.id) }
            }
            HStack(spacing: 8) {
                if let model = detail?.model ?? card.thread.model {
                    Label(model, systemImage: "cpu").lineLimit(1)
                }
                if let branch = detail?.branch ?? card.thread.branch {
                    Label(branch, systemImage: "arrow.triangle.branch").lineLimit(1)
                }
                ElapsedLabel(start: detail?.runStartedAt ?? card.thread.runStartedAt,
                             end: card.state == .done ? detail?.runCompletedAt : nil)
                    .fixedSize()
            }
            .labelStyle(CompactLabel())
            .font(.system(size: 9.5))
            .foregroundStyle(T3Theme.muted)
        }
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8))
            configuration.title
        }
    }
}

struct ElapsedLabel: View {
    let start: Date?
    let end: Date?

    var body: some View {
        if let start {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Label(Format.elapsed((end ?? timeline.date).timeIntervalSince(start)), systemImage: "timer")
                    .monospacedDigit()
            }
        }
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovered ? T3Theme.primary : T3Theme.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovered ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .help(help)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
    }
}

struct ProviderBadge: View {
    let providerId: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(T3Theme.accent(providerId: providerId).opacity(0.22))
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(T3Theme.accent(providerId: providerId))
        }
        .frame(width: 26, height: 26)
        .help(InboxBuilder.displayName(provider: providerId))
    }

    private var symbol: String {
        switch providerId {
        case "claudeAgent", "claude": "asterisk"
        case "codex": "chevron.left.forwardslash.chevron.right"
        default: "sparkle"
        }
    }
}

struct PlanChecklist: View {
    let plan: PlanProgress
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("PLAN").font(.system(size: 9, weight: .semibold)).tracking(0.6)
                Spacer()
                Text("\(plan.completed)/\(plan.steps.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(T3Theme.muted)
            ForEach(plan.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CheckMark(status: step.status, live: live)
                    Text(step.text)
                        .font(.system(size: 11, weight: step.status == "running" ? .semibold : .regular))
                        .foregroundStyle(step.status == "completed" ? T3Theme.muted
                                         : step.status == "running" ? T3Theme.primary : T3Theme.secondary)
                        .strikethrough(step.status == "completed", color: T3Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: plan.steps)
    }
}

struct CheckMark: View {
    let status: String
    let live: Bool
    @State private var bounce = 0
    @State private var pop = false

    var body: some View {
        Group {
            switch status {
            case "completed":
                Image(systemName: "checkmark.circle.fill").foregroundStyle(T3Theme.working)
            case "running":
                Image(systemName: "circle.dotted").foregroundStyle(live ? T3Theme.needsYou : T3Theme.muted)
            default:
                Image(systemName: "circle").foregroundStyle(T3Theme.muted)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .symbolEffect(.bounce, value: bounce)
        .scaleEffect(pop ? 1.35 : 1)
        .onChange(of: status) { old, new in
            guard new == "completed", old != "completed" else { return }
            bounce += 1
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
            }
        }
    }
}

struct ActivityFeed: View {
    let entries: [ActivityEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ACTIVITY").font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(T3Theme.muted)
            ForEach(entries.reversed()) { entry in
                HStack(spacing: 6) {
                    Image(systemName: icon(entry.kind))
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12)
                    Text(entry.text)
                        .font(entry.kind == .command ? .system(size: 10.5, design: .monospaced) : .system(size: 10.5))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.inProgress {
                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                    }
                }
                .foregroundStyle(entry.failed ? T3Theme.failed : entry.inProgress ? T3Theme.replied : T3Theme.muted)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: entries)
    }

    private func icon(_ kind: ActivityEntry.Kind) -> String {
        switch kind {
        case .command: "terminal"
        case .edit: "pencil"
        case .tool: "wrench.and.screwdriver"
        case .search: "magnifyingglass"
        case .agent: "person.2"
        case .thinking: "brain"
        case .message: "text.bubble"
        }
    }
}
