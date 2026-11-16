import SwiftUI
import T3IsleCore

struct T3HeadphonesActivity: View {
    let connect: HeadphonesConnect

    var body: some View {
        T3ClosedEars {
            HStack(spacing: 6) {
                Image(systemName: connect.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(T3Theme.primary)
                Text(connect.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T3Theme.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } right: {
            HeadphonesBatteryGlance(kind: connect.kind, battery: connect.battery)
        }
        .help(connect.name)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(T3Theme.act, value: connect.battery)
    }
}

struct HeadphonesBatteryGlance: View {
    let kind: HeadphonesKind
    let battery: HeadphonesBattery

    var body: some View {
        HStack(spacing: 8) {
            if battery.isEmpty {
                Text("Connected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T3Theme.secondary)
            }
            if let left = battery.left { level(left, symbol: kind.budSymbol(.left)) }
            if let right = battery.right { level(right, symbol: kind.budSymbol(.right)) }
            if let single = battery.single, battery.left == nil, battery.right == nil {
                level(single, symbol: nil)
            }
            if let chargingCase = battery.chargingCase { level(chargingCase, symbol: kind.caseSymbol) }
        }
    }

    private func level(_ percent: Int, symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(T3Theme.secondary)
            }
            RingGauge(fraction: Double(percent) / 100, color: percent <= 20 ? T3Theme.failed : T3Theme.working)
                .frame(width: 11, height: 11)
            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(T3Theme.primary)
        }
    }
}

private extension HeadphonesKind {
    enum Bud { case left, right }

    var symbol: String {
        switch self {
        case .airpods: "airpods"
        case .airpodsPro: "airpodspro"
        case .airpodsMax: "airpodsmax"
        case .beats: "beats.headphones"
        case .headphones: "headphones"
        }
    }

    func budSymbol(_ bud: Bud) -> String {
        switch (self, bud) {
        case (.airpodsPro, .left): "airpodpro.left"
        case (.airpodsPro, .right): "airpodpro.right"
        case (_, .left): "airpod.left"
        case (_, .right): "airpod.right"
        }
    }

    var caseSymbol: String {
        self == .airpodsPro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
    }
}
