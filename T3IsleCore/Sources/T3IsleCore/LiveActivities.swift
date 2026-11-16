import Foundation

public enum ClosedActivity: Equatable, Sendable {
    case none
    case t3
    case nowPlaying
    case headphones(HeadphonesConnect)

    public static func resolve(t3: ClosedPresence, headphones: HeadphonesConnect?, nowPlaying: Bool) -> ClosedActivity {
        if t3 == .alert { return .t3 }
        if let headphones { return .headphones(headphones) }
        if nowPlaying { return .nowPlaying }
        return t3 == .threads ? .t3 : .none
    }

    public var headphones: HeadphonesConnect? {
        if case .headphones(let connect) = self { return connect }
        return nil
    }
}

public enum HeadphonesKind: Equatable, Sendable {
    case airpods, airpodsPro, airpodsMax, beats, headphones

    static let appleProductIDs: [Int: HeadphonesKind] = [
        0x2002: .airpods, 0x200F: .airpods, 0x2013: .airpods, 0x2019: .airpods, 0x201B: .airpods,
        0x200A: .airpodsMax, 0x201F: .airpodsMax,
        0x200E: .airpodsPro, 0x2014: .airpodsPro, 0x2024: .airpodsPro, 0x2027: .airpodsPro,
        0x2017: .beats, 0x2009: .beats, 0x2006: .beats, 0x200C: .beats,
    ]

    public init(productID: Int?, name: String) {
        if let productID, let kind = Self.appleProductIDs[productID] {
            self = kind
            return
        }
        let name = name.lowercased()
        if name.contains("airpods max") {
            self = .airpodsMax
        } else if name.contains("airpods pro") {
            self = .airpodsPro
        } else if name.contains("airpods") {
            self = .airpods
        } else if name.contains("beats") {
            self = .beats
        } else {
            self = .headphones
        }
    }
}

public struct HeadphonesBattery: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var single: Int?

    public init(left: Int? = nil, right: Int? = nil, single: Int? = nil) {
        self.left = left
        self.right = right
        self.single = single
    }

    public var isEmpty: Bool { level == nil }

    public var level: Int? {
        switch (left, right) {
        case let (left?, right?): min(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): single
        }
    }
}

public struct HeadphonesConnect: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let address: String
    public let name: String
    public let kind: HeadphonesKind
    public var battery: HeadphonesBattery

    public init(id: UUID = UUID(), address: String, name: String, kind: HeadphonesKind,
                battery: HeadphonesBattery = HeadphonesBattery()) {
        self.id = id
        self.address = address
        self.name = name
        self.kind = kind
        self.battery = battery
    }
}

public struct BluetoothReport: Equatable, Sendable {
    public let name: String
    public let productID: Int?
    public let battery: HeadphonesBattery

    public static func find(address: String, inSystemProfilerJSON data: Data) -> BluetoothReport? {
        let target = normalizedAddress(address)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for section in sections {
            for (key, value) in section where key.hasPrefix("device_") {
                for entry in value as? [[String: Any]] ?? [] {
                    for (name, payload) in entry {
                        guard let payload = payload as? [String: Any],
                              let deviceAddress = payload["device_address"] as? String,
                              normalizedAddress(deviceAddress) == target else { continue }
                        return BluetoothReport(name: name, payload: payload)
                    }
                }
            }
        }
        return nil
    }

    init(name: String, payload: [String: Any]) {
        self.name = name
        productID = (payload["device_productID"] as? String).flatMap(Self.hex)
        battery = HeadphonesBattery(
            left: Self.percent(payload["device_batteryLevelLeft"]),
            right: Self.percent(payload["device_batteryLevelRight"]),
            single: Self.percent(payload["device_batteryLevelMain"] ?? payload["device_batteryLevel"])
        )
    }

    static func normalizedAddress(_ address: String) -> String {
        address.lowercased().filter(\.isHexDigit)
    }

    static func hex(_ text: String) -> Int? {
        Int(text.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16)
    }

    static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String,
              let number = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        else { return nil }
        return min(max(number, 0), 100)
    }
}

@MainActor
public final class HeadphonesPopup: ObservableObject {
    @Published public private(set) var current: HeadphonesConnect?

    public let showFor: Duration
    private var hideTask: Task<Void, Never>?

    public init(showFor: Duration = .seconds(4)) {
        self.showFor = showFor
    }

    public func show(_ connect: HeadphonesConnect) {
        current = connect
        hideTask?.cancel()
        hideTask = Task { [weak self, showFor, id = connect.id] in
            try? await Task.sleep(for: showFor)
            guard !Task.isCancelled, self?.current?.id == id else { return }
            self?.current = nil
        }
    }

    public func update(battery: HeadphonesBattery, for id: UUID) {
        guard current?.id == id, !battery.isEmpty else { return }
        current?.battery = battery
    }

    public func dismiss() {
        hideTask?.cancel()
        current = nil
    }
}
