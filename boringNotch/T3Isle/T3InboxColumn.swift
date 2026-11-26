import Defaults
import SwiftUI
import T3IsleCore

struct T3InboxColumn: View {
    @ObservedObject var model: T3IsleModel
    @Default(.t3CollapsedSections) private var collapsed
    @Default(.t3ThreadActions) private var threadActions
    @Default(.t3ShowQuotaLeft) private var showQuotaLeft
    @Default(.t3QuotaWarnAt) private var warnAt
    @Default(.t3QuotaCriticalAt) private var criticalAt
    @Namespace private var rows

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let now = timeline.date
            let visible = model.threads.filter { !$0.isSnoozed }
            let waiting = visible.filter { !$0.mood.isBusy }
            let working = visible.filter { $0.mood.isBusy }
            let snoozed = model.threads.filter(\.isSnoozed)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Limits", isOpen: isOpen(.limits)) { toggle(.limits) }
                    if isOpen(.limits) {
                        LimitCards(providers: model.providers, showLeft: showQuotaLeft, warnAt: warnAt,
                                   criticalAt: criticalAt, now: now)
                    }
                    Rectangle().fill(T3Theme.hairline).frame(height: 1).padding(.vertical, 2)
                    if waiting.isEmpty && working.isEmpty && snoozed.isEmpty {
                        Text(model.connection == .live ? "No open threads" : connectionText)
                            .font(.system(size: 11))
                            .foregroundStyle(T3Theme.muted)
                            .padding(.horizontal, 8)
                    }
                    if !waiting.isEmpty {
                        SectionHeader(title: "Waiting on you", count: waiting.count, isOpen: isOpen(.waiting)) { toggle(.waiting) }
                        if isOpen(.waiting) {
                            ForEach(waiting) { thread in
                                row(thread, now: now, actions: thread.mood == .needsYou ? .none : .organize)
                            }
                        }
                    }
                    if !working.isEmpty {
                        SectionHeader(title: "Working", count: working.count, isOpen: isOpen(.working)) { toggle(.working) }
                        if isOpen(.working) {
                            ForEach(working) { thread in row(thread, now: now, actions: .none) }
                        }
                    }
                    if let wake = snoozed.compactMap(\.snoozedUntil).min() {
                        SectionHeader(title: "Snoozed", count: snoozed.count,
                                      detail: "back in \(Format.duration(wake.timeIntervalSince(now)))",
                                      isOpen: isOpen(.snoozed)) { toggle(.snoozed) }
                        if isOpen(.snoozed) {
                            ForEach(snoozed) { thread in row(thread, now: now, actions: .wake) }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .animation(model.motionIsAction ? T3Theme.act : T3Theme.shuffle, value: model.threads)
    }

    private var connectionText: String {
        if case .offline(let message) = model.connection { return message }
        return "Connecting to T3 Code…"
    }

    private func row(_ thread: T3Thread, now: Date, actions: RowActions) -> some View {
        ThreadRow(thread: thread, now: now, actions: threadActions ? actions : .none,
                  onOpen: { model.open(thread.id) },
                  onSettle: { model.settle(thread) },
                  onSnooze: { model.snooze(thread, until: $0) },
                  onWake: { model.wake(thread) },
                  onHover: { model.hold(thread.id, $0) })
            .matchedGeometryEffect(id: thread.id, in: rows)
    }

    private func isOpen(_ section: InboxSection) -> Bool {
        !collapsed.contains(section.rawValue)
    }

    private func toggle(_ section: InboxSection) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if isOpen(section) { collapsed.insert(section.rawValue) } else { collapsed.remove(section.rawValue) }
        }
    }
}

struct LimitCards: View {
    let providers: [ProviderLimits]
    let showLeft: Bool
    let warnAt: Int
    let criticalAt: Int
    let now: Date

    var body: some View {
        if providers.isEmpty {
            Text("No usage limits cached by T3 yet")
                .font(.system(size: 11))
                .foregroundStyle(T3Theme.muted)
                .padding(.horizontal, 8)
        } else {
            HStack(alignment: .top, spacing: 6) {
                ForEach(providers.prefix(2)) { provider in
                    LimitCard(provider: provider, showLeft: showLeft, warnAt: warnAt, criticalAt: criticalAt, now: now)
                }
            }
        }
    }
}

struct LimitCard: View {
    let provider: ProviderLimits
    let showLeft: Bool
    let warnAt: Int
    let criticalAt: Int
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(T3Theme.accent(provider)).frame(width: 6, height: 6)
                Text(provider.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T3Theme.primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let checked = provider.checkedAt {
                    let ago = Format.ago(checked, now: now)
                    Text(ago == "now" ? "now" : ago)
                        .font(.system(size: 9))
                        .foregroundStyle(T3Theme.muted)
                        .help("When T3 last checked these limits")
                }
            }
            if let note = provider.note {
                Text(note)
                    .font(.system(size: 9))
                    .foregroundStyle(T3Theme.needsYou)
                    .lineLimit(2)
            }
            ForEach(provider.windows.prefix(2)) { window in
                LimitBar(window: window, showLeft: showLeft, warnAt: warnAt, criticalAt: criticalAt, now: now)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(T3Theme.card))
    }
}

struct LimitBar: View {
    let window: LimitWindow
    let showLeft: Bool
    let warnAt: Int
    let criticalAt: Int
    let now: Date

    var body: some View {
        let left = window.remaining(at: now)
        let shown = showLeft ? left : 100 - left
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.label)
                    .font(.system(size: 10))
                    .foregroundStyle(T3Theme.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text("\(Int(shown.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T3Theme.primary)
                    .fixedSize()
            }
            .help(window.resetsAt.map { "Resets in \(Format.duration($0.timeIntervalSince(now)))" } ?? window.label)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(T3Theme.level(left: left, warnAt: warnAt, criticalAt: criticalAt))
                        .frame(width: max(4, proxy.size.width * shown / 100))
                }
            }
            .frame(height: 3)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int?
    var detail: String?
    let isOpen: Bool
    let toggle: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Text(title.uppercased()).tracking(0.6)
                if let detail { Text("· \(detail)").fontWeight(.regular) }
                Spacer(minLength: 8)
                if let count { Text("\(count)").contentTransition(.numericText()) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(hovered ? T3Theme.secondary : T3Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

enum RowActions {
    case none, organize, wake
}

private enum Reaction {
    case settle, snooze, wake
}

struct ThreadRow: View {
    let thread: T3Thread
    let now: Date
    var actions = RowActions.none
    let onOpen: () -> Void
    var onSettle: () -> Void = {}
    var onSnooze: (Date) -> Void = { _ in }
    var onWake: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    @State private var hovered = false
    @State private var choosingSnooze = false
    @State private var reaction: Reaction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snoozed = thread.isSnoozed
        let asleep = reaction == .snooze || (snoozed && reaction != .wake)
        let showActions = actions != .none && hovered && reaction == nil
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    avatar(asleep: asleep)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(thread.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(thread.mood.isBusy || asleep ? T3Theme.secondary : T3Theme.primary)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Text(thread.project)
                                .font(.system(size: 9.5))
                                .foregroundStyle(T3Theme.muted)
                                .lineLimit(1)
                            if let environment = thread.environment {
                                Label(environment.label, systemImage: "desktopcomputer")
                                    .font(.system(size: 9))
                                    .foregroundStyle(T3Theme.muted)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        LiveLine(text: thread.line, attention: !thread.mood.isBusy && !asleep)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ZStack(alignment: .trailing) {
                if let reaction {
                    outcome(reaction).transition(swap)
                } else if showActions && choosingSnooze {
                    SnoozeChoices(now: now) { until in commit(.snooze) { onSnooze(until) } }
                        .fixedSize()
                        .transition(swap)
                } else if showActions {
                    HStack(spacing: 4) {
                        if actions == .organize {
                            RowButton(icon: "moon.zzz.fill", help: "Snooze") {
                                withAnimation(.easeOut(duration: 0.18)) { choosingSnooze = true }
                            }
                            RowButton(icon: "checkmark", help: "Settle") { commit(.settle, onSettle) }
                        } else {
                            RowButton(icon: "sun.max.fill", help: "Wake up now") { commit(.wake, onWake) }
                        }
                    }
                    .transition(swap)
                } else {
                    status(snoozed: snoozed)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onOpen)
                        .transition(swap)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovered ? Color.white.opacity(0.07) : .clear))
        .onHover { inside in
            onHover(inside)
            withAnimation(.easeOut(duration: 0.15)) {
                hovered = inside
                if !inside { choosingSnooze = false }
            }
        }
        .onDisappear { onHover(false) }
        .task(id: reaction) {
            guard reaction != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            reaction = nil
        }
        .transition(.asymmetric(insertion: .opacity, removal: exit))
    }

    private func avatar(asleep: Bool) -> some View {
        BlobAvatar(seed: thread.id, mood: reaction == .settle ? .replied : thread.mood, size: 24,
                   muted: asleep, sleeping: asleep)
            .overlay(alignment: .bottomTrailing) {
                if reaction == .settle {
                    Circle()
                        .fill(T3Theme.working)
                        .frame(width: 11, height: 11)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 6, weight: .heavy)).foregroundStyle(.black))
                        .offset(x: 2, y: 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if reaction == .snooze && !reduceMotion { FloatingZ().offset(x: 4, y: -2) }
            }
    }

    private func status(snoozed: Bool) -> some View {
        let wake = snoozed ? thread.snoozedUntil : nil
        return VStack(alignment: .trailing, spacing: 1) {
            Text(snoozed ? "Snoozed" : thread.status)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(snoozed ? T3Theme.muted : T3Theme.mood(thread.mood))
                .lineLimit(1)
            Text(wake.map { "in \(Format.duration($0.timeIntervalSince(now)))" }
                ?? Format.ago(thread.since ?? thread.updatedAt, now: now))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(T3Theme.muted)
        }
    }

    private func outcome(_ reaction: Reaction) -> some View {
        Text(reaction == .settle ? "Settled" : reaction == .snooze ? "Snoozed" : "Awake")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(reaction == .settle ? T3Theme.working : reaction == .snooze ? T3Theme.muted : T3Theme.needsYou)
    }

    private func commit(_ reaction: Reaction, _ perform: @escaping () -> Void) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            self.reaction = reaction
            choosingSnooze = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.28), execute: perform)
    }

    private var exit: AnyTransition {
        let quick = Animation.easeOut(duration: 0.15)
        if reduceMotion { return .opacity.animation(quick) }
        switch reaction {
        case .settle: return .offset(x: 36).combined(with: .opacity).animation(quick)
        case .snooze: return .offset(y: 6).combined(with: .scale(scale: 0.97)).combined(with: .opacity).animation(quick)
        case .wake, nil: return .opacity
        }
    }

    private var swap: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)).combined(with: .blurred)
    }
}

struct LiveLine: View {
    let text: String?
    let attention: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            if let text {
                Text(text)
                    .font(text.hasPrefix("$ ") ? .system(size: 10, design: .monospaced) : .system(size: 10.5))
                    .foregroundStyle(attention ? T3Theme.secondary : T3Theme.muted)
                    .lineLimit(1)
                    .id(text)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: 6).combined(with: .opacity).combined(with: .blurred),
                        removal: .offset(y: -6).combined(with: .opacity).combined(with: .blurred)
                    ))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 13, alignment: .leading)
        .clipped()
        .animation(.easeOut(duration: 0.22), value: text)
    }
}

struct RowButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
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

struct SnoozeChoices: View {
    let now: Date
    let choose: (Date) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(SnoozeOption.choices(from: now).enumerated()), id: \.offset) { index, option in
                SnoozeChip(title: option.title, help: Format.clock(option.date, now: now), delay: Double(index) * 0.03) {
                    choose(option.date)
                }
            }
        }
    }
}

private struct SnoozeChip: View {
    let title: String
    let help: String
    let delay: Double
    let action: () -> Void
    @State private var shown = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovered ? T3Theme.primary : T3Theme.secondary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(hovered ? 0.16 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .help(help)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
        .opacity(shown ? 1 : 0)
        .offset(x: shown || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(.easeOut(duration: 0.2).delay(delay)) { shown = true } }
    }
}

private struct FloatingZ: View {
    @State private var up = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(0..<2) { index in
                Text("z")
                    .font(.system(size: index == 0 ? 9 : 7, weight: .heavy, design: .rounded))
                    .foregroundStyle(T3Theme.secondary)
                    .offset(x: CGFloat(index) * 5, y: up ? -9 - CGFloat(index) * 4 : 0)
                    .opacity(up ? 0 : 1)
                    .animation(.easeOut(duration: 0.55).delay(Double(index) * 0.08), value: up)
            }
        }
        .onAppear { up = true }
    }
}
