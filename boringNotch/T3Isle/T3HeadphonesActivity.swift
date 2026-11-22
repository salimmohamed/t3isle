import SwiftUI
import T3IsleCore

struct T3HeadphonesActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let connect: HeadphonesConnect

    private let earWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: connect.kind.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(T3Theme.primary)
                .frame(width: earWidth)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            HeadphonesBatteryGlance(level: connect.battery.level)
                .frame(width: earWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .help(connect.name)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct HeadphonesBatteryGlance: View {
    let level: Int?

    var body: some View {
        if let level {
            HStack(spacing: 4) {
                Text("\(level)%")
                    .lineLimit(1)
                    .fixedSize()
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(T3Theme.primary)
                BatteryBar(fraction: Double(level) / 100, color: level <= 20 ? T3Theme.failed : T3Theme.working)
                    .frame(width: 20, height: 10)
            }
            .contentTransition(.numericText())
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(T3Theme.working)
        }
    }
}

struct BatteryBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color)
                            .frame(width: max(2, (proxy.size.width - 4) * min(1, max(0, fraction))),
                                   height: max(0, proxy.size.height - 4))
                            .offset(x: 2, y: 2)
                    }
                }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
    }
}
