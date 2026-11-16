import Defaults
import SwiftUI
import T3IsleCore

struct T3ClosedActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var model = T3IsleRuntime.shared.model
    @Default(.t3QuotaWindow) private var quotaWindow
    @Default(.t3ShowQuotaLeft) private var showQuotaLeft
    @Default(.t3QuotaWarnAt) private var warnAt
    @Default(.t3QuotaCriticalAt) private var criticalAt
    @Default(.t3FacesPerGroup) private var facesPerGroup

    private var faceSize: CGFloat { max(12, min(20, vm.effectiveClosedNotchHeight - 10)) }

    var body: some View {
        T3ClosedEars { left } right: { right }
            .animation(T3Theme.shuffle, value: model.threads)
    }

    @ViewBuilder
    private var left: some View {
        if let banner = model.banner {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(T3Theme.working)
                Text("Plan done").foregroundStyle(T3Theme.primary)
            }
            .font(.system(size: 11, weight: .semibold))
            .help(banner.threadTitle)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else {
            ThreadGlance(threads: model.threads.filter { !$0.isSnoozed }, size: faceSize, facesPerGroup: facesPerGroup)
        }
    }

    @ViewBuilder
    private var right: some View {
        if !model.prompts.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.bubble.fill")
                Text("\(model.prompts.count)").monospacedDigit()
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(T3Theme.attention)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else {
            LimitGlance(providers: model.providers, window: quotaWindow, showLeft: showQuotaLeft,
                        warnAt: warnAt, criticalAt: criticalAt)
        }
    }
}

struct T3ClosedEars<Left: View, Right: View>: View {
    @EnvironmentObject var vm: BoringViewModel
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right
    @State private var leftWidth: CGFloat = 0
    @State private var rightWidth: CGFloat = 0

    var body: some View {
        let ear = max(leftWidth, rightWidth, 40)
        HStack(spacing: 0) {
            left
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { leftWidth = $0 }
                .frame(width: ear, alignment: .trailing)
                .padding(.trailing, 6)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            right
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { rightWidth = $0 }
                .frame(width: ear, alignment: .leading)
                .padding(.leading, 6)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct ThreadGlance: View {
    let threads: [T3Thread]
    let size: CGFloat
    let facesPerGroup: Int
    @Namespace private var faces

    var body: some View {
        let working = threads.filter { $0.mood.isBusy }
        let waiting = threads.filter { !$0.mood.isBusy }
        HStack(spacing: 6) {
            if working.isEmpty && waiting.isEmpty {
                BlobAvatar(seed: "t3-isle", mood: .idle, size: size, muted: true)
            }
            if !waiting.isEmpty { group(waiting) }
            if !working.isEmpty && !waiting.isEmpty {
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 1, height: size * 0.6)
            }
            if !working.isEmpty { group(working) }
        }
    }

    private func group(_ threads: [T3Thread]) -> some View {
        HStack(spacing: 3) {
            HStack(spacing: -size * 0.3) {
                ForEach(threads.prefix(facesPerGroup)) { thread in
                    BlobAvatar(seed: thread.id, mood: thread.mood, size: size)
                        .matchedGeometryEffect(id: thread.id, in: faces)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            if threads.count > facesPerGroup {
                Text("+\(threads.count - facesPerGroup)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(T3Theme.secondary)
            }
        }
    }
}

struct LimitGlance: View {
    let providers: [ProviderLimits]
    let window: QuotaWindowChoice
    let showLeft: Bool
    let warnAt: Int
    let criticalAt: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            HStack(spacing: 8) {
                if providers.allSatisfy({ $0.windows.isEmpty }) {
                    Text("–").font(.system(size: 11, weight: .semibold)).foregroundStyle(T3Theme.muted)
                }
                ForEach(providers) { provider in
                    if let limit = provider.tightest(at: now, kind: window.kind) {
                        let left = limit.remaining(at: now)
                        let shown = showLeft ? left : 100 - left
                        HStack(spacing: 4) {
                            RingGauge(fraction: shown / 100, color: T3Theme.accent(provider))
                                .frame(width: 12, height: 12)
                            Text("\(Int(shown.rounded()))%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(left <= Double(warnAt)
                                    ? T3Theme.level(left: left, warnAt: warnAt, criticalAt: criticalAt) : T3Theme.primary)
                        }
                        .help("\(provider.name) · \(limit.label): \(Int(shown.rounded()))% \(showLeft ? "left" : "used")")
                    }
                }
            }
        }
    }
}

struct RingGauge: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
