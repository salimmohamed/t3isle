import AppKit
import Defaults
import SwiftUI
import T3IsleCore

struct T3NotchView: View {
    @ObservedObject var model = T3IsleRuntime.shared.model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let banner = model.banner {
                PlanBannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !model.prompts.isEmpty {
                T3QuestionCarousel(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: 10) {
                T3InboxColumn(model: model)
                    .frame(width: 250)
                T3AgentsColumn(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.prompts.isEmpty)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.banner)
        .onAppear { model.expanded = true }
        .onDisappear { model.expanded = false }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                if let notice = model.notice {
                    HStack(spacing: 2) {
                        Text(notice.text)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(notice.isError ? T3Theme.failed : T3Theme.secondary)
                            .lineLimit(1)
                        if notice.undo != nil {
                            PromptButton(title: "Undo", style: .ghost) { model.undo() }
                        }
                    }
                    .fixedSize()
                    .id(notice.id)
                    .transition(.opacity.combined(with: .offset(y: 4)).combined(with: .blurred))
                } else {
                    ConnectionBadge(state: model.connection, demo: model.isDemo)
                        .transition(.opacity)
                }
            }
            .animation(T3Theme.act, value: model.notice?.id)
            Spacer()
            PromptButton(title: "Open T3 Code", style: .ghost) { model.open(nil) }
        }
        .frame(height: 22)
    }
}

private struct ConnectionBadge: View {
    let state: ConnectionState
    let demo: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 10))
        .foregroundStyle(T3Theme.muted)
        .padding(.leading, 6)
    }

    private var text: String {
        if demo { return "Demo data" }
        switch state {
        case .connecting: return "Connecting…"
        case .live: return "Live"
        case .offline(let message): return message
        }
    }

    private var color: Color {
        if demo { return T3Theme.replied }
        switch state {
        case .connecting: return T3Theme.needsYou
        case .live: return T3Theme.working
        case .offline: return T3Theme.failed
        }
    }
}

private struct PlanBannerView: View {
    let banner: PlanBanner

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13))
                .foregroundStyle(T3Theme.working)
                .symbolEffect(.bounce, value: banner.id)
            Text("Plan complete")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(T3Theme.primary)
            Text("\(banner.threadTitle) · \(banner.stepCount) steps")
                .font(.system(size: 11))
                .foregroundStyle(T3Theme.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T3Theme.working.opacity(0.14)))
    }
}

struct T3AttentionBorder<S: Shape>: View {
    let shape: S
    @ObservedObject var model = T3IsleRuntime.shared.model
    @ObservedObject var preview = T3BorderPreview.shared
    @Default(.t3Enabled) private var enabled
    @Default(.t3AttentionBorder) private var borderShown
    @Default(.t3AttentionBorderHex) private var hex

    private var visible: Bool { enabled && borderShown && (model.needsAttention || preview.isActive) }

    var body: some View {
        let color = Color(hex: hex)
        shape
            .stroke(color, lineWidth: 1.5)
            .opacity(visible ? 1 : 0)
            .shadow(color: color.opacity(visible ? 0.6 : 0), radius: 6)
            .animation(.easeInOut(duration: 0.3), value: visible)
            .animation(.easeInOut(duration: 0.2), value: hex)
            .allowsHitTesting(false)
    }
}

struct T3Integration: ViewModifier {
    @ObservedObject var vm: BoringViewModel
    @ObservedObject var model = T3IsleRuntime.shared.model
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var openedByT3 = false
    @State private var closeTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.promptArrivals) { _, _ in
                guard Defaults[.t3Enabled], !model.prompts.isEmpty else { return }
                if Defaults[.t3QuestionSound] { NSSound(named: "Glass")?.play() }
                guard Defaults[.t3OpenOnQuestion] else { return }
                show(holdFor: nil)
            }
            .onChange(of: model.prompts.isEmpty) { _, empty in
                guard empty, openedByT3 else { return }
                closeSoon(after: 0.8)
            }
            .onChange(of: model.banner) { _, banner in
                guard banner != nil, Defaults[.t3Enabled] else { return }
                if vm.notchState == .closed { show(holdFor: 4) }
            }
            .onChange(of: coordinator.currentView) { _, view in
                guard vm.notchState == .open else { return }
                vm.notchSize = T3Tabs.openSize(for: view, base: openNotchSize)
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .closed {
                    openedByT3 = false
                    closeTask?.cancel()
                } else if coordinator.currentView == .home && !coordinator.openLastTabByDefault {
                    coordinator.currentView = T3Tabs.defaultView(fallback: .home)
                }
            }
    }

    private func show(holdFor seconds: TimeInterval?) {
        closeTask?.cancel()
        coordinator.currentView = .t3
        if vm.notchState == .closed {
            openedByT3 = true
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { vm.open() }
        } else {
            vm.notchSize = T3Tabs.openSize(for: .t3, base: openNotchSize)
        }
        if let seconds { closeSoon(after: seconds) }
    }

    private func closeSoon(after seconds: TimeInterval) {
        closeTask?.cancel()
        closeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, openedByT3, model.prompts.isEmpty, !vm.isMouseHovering() else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 1)) { vm.close() }
        }
    }
}

extension View {
    func t3Integration(vm: BoringViewModel) -> some View {
        modifier(T3Integration(vm: vm))
    }
}
