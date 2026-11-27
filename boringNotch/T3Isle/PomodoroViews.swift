import Defaults
import SwiftUI
import T3IsleCore

struct PomodoroControl: View {
    @ObservedObject private var timer = T3IsleRuntime.shared.pomodoro

    var body: some View {
        HStack(spacing: 6) {
            PomodoroTime(timer: timer)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(timer.isActive ? timer.phase.tint : T3Theme.primary)
                .help(timer.phase.title)
            Button(action: toggle) {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 14)
            }
            .help(timer.isRunning ? "Pause" : timer.isActive ? "Resume" : "Start a 25-minute focus block")
            if timer.isActive {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .imageScale(.small)
        .buttonStyle(.plain)
        .foregroundStyle(T3Theme.primary)
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(Capsule().fill(.black))
        .animation(T3Theme.liveActivityIn, value: timer.isActive)
    }

    private func toggle() {
        if timer.isRunning { timer.pause() } else { timer.start() }
    }
}

struct PomodoroClosedActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var timer = T3IsleRuntime.shared.pomodoro

    private let earWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: timer.isRunning ? timer.phase.symbol : "pause.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(timer.phase.tint)
                .frame(width: earWidth)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            PomodoroTime(timer: timer)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(timer.isRunning ? T3Theme.primary : T3Theme.secondary)
                .frame(width: earWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .help(timer.phase.title)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct PomodoroSettings: View {
    var body: some View {
        Section {
            Defaults.Toggle(key: .pomodoroTimer) { Text("Show a Pomodoro timer") }
        } header: {
            Text("Pomodoro")
        } footer: {
            Text("Adds a timer to the open notch for a 25-minute focus block followed by a 5-minute break. The closed notch shows the countdown while a block runs.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PomodoroTime: View {
    @ObservedObject var timer: PomodoroTimer

    var body: some View {
        if let endsAt = timer.endsAt {
            TimelineView(.periodic(from: endsAt.addingTimeInterval(-PomodoroTimer.focusLength), by: 1)) { context in
                label(at: context.date)
            }
        } else {
            label(at: .now)
        }
    }

    private func label(at date: Date) -> some View {
        Text(timer.countdown(at: date))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

private extension PomodoroPhase {
    var symbol: String {
        switch self {
        case .idle, .focus: "timer"
        case .rest: "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: T3Theme.secondary
        case .focus: Color(hex: "#FF7A59")
        case .rest: T3Theme.working
        }
    }

    var title: String {
        switch self {
        case .idle: "Pomodoro"
        case .focus: "Focus"
        case .rest: "Break"
        }
    }
}
