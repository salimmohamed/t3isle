import CoreBluetooth
import Foundation

public enum ClosedActivity: Equatable, Sendable {
    case none
    case t3
    case nowPlaying
    case headphones(HeadphonesConnect)
    case pomodoro

    public static func resolve(t3: ClosedPresence, headphones: HeadphonesConnect?, pomodoro: Bool = false,
                               nowPlaying: Bool) -> ClosedActivity {
        if t3 == .alert { return .t3 }
        if let headphones { return .headphones(headphones) }
        if pomodoro { return .pomodoro }
        if nowPlaying { return .nowPlaying }
        return t3 == .none ? .none : .t3
    }

    public var headphones: HeadphonesConnect? {
        if case .headphones(let connect) = self { return connect }
        return nil
    }
}

public enum BluetoothAudioClass: String, CaseIterable, Sendable {
    case headphones, speaker, car

    static let audioVideoMajor: UInt32 = 0x04

    public static func isAudioVideo(classOfDevice: UInt32) -> Bool {
        (classOfDevice >> 8) & 0x1F == audioVideoMajor
    }

    public init?(classOfDevice: UInt32) {
        guard Self.isAudioVideo(classOfDevice: classOfDevice) else { return nil }
        switch (classOfDevice >> 2) & 0x3F {
        case 0x01, 0x06: self = .headphones
        case 0x05, 0x07, 0x0A: self = .speaker
        case 0x08: self = .car
        default: return nil
        }
    }

    public var classOfDevice: UInt32 {
        let minor: UInt32 = switch self {
        case .headphones: 0x06
        case .speaker: 0x05
        case .car: 0x08
        }
        return 0x240000 | Self.audioVideoMajor << 8 | minor << 2
    }
}

public enum HeadphonesKind: Equatable, Sendable {
    case airpods, airpodsGen3, airpodsPro, airpodsMax
    case beatsHeadphones, beatsEarphones, powerbeats, powerbeatsPro, beatsStudioBuds, beatsFitPro
    case headphones, speaker, carAudio

    static let appleProductIDs: [Int: HeadphonesKind] = [
        0x2002: .airpods, 0x200F: .airpods,
        0x2013: .airpodsGen3, 0x2019: .airpodsGen3, 0x201B: .airpodsGen3,
        0x200E: .airpodsPro, 0x2014: .airpodsPro, 0x2024: .airpodsPro, 0x2027: .airpodsPro,
        0x200A: .airpodsMax, 0x201F: .airpodsMax,
        0x2006: .beatsHeadphones, 0x2009: .beatsHeadphones, 0x200C: .beatsHeadphones, 0x2017: .beatsHeadphones,
        0x2025: .beatsHeadphones,
        0x2005: .beatsEarphones, 0x2010: .beatsEarphones,
        0x2003: .powerbeats, 0x200D: .powerbeats,
        0x200B: .powerbeatsPro, 0x201D: .powerbeatsPro,
        0x2011: .beatsStudioBuds, 0x2016: .beatsStudioBuds, 0x2026: .beatsStudioBuds,
        0x2012: .beatsFitPro,
    ]

    static let nameHints: [(String, HeadphonesKind)] = [
        ("airpods max", .airpodsMax), ("airpods pro", .airpodsPro), ("airpods", .airpods),
        ("powerbeats pro", .powerbeatsPro), ("powerbeats", .powerbeats),
        ("studio buds", .beatsStudioBuds), ("solo buds", .beatsStudioBuds), ("fit pro", .beatsFitPro),
        ("beats flex", .beatsEarphones), ("beatsx", .beatsEarphones), ("beats", .beatsHeadphones),
    ]

    public init(appleProductID: Int?, classOfDevice: UInt32?, name: String) {
        if let appleProductID, let kind = Self.appleProductIDs[appleProductID] {
            self = kind
            return
        }
        switch classOfDevice.flatMap(BluetoothAudioClass.init(classOfDevice:)) {
        case .speaker:
            self = .speaker
        case .car:
            self = .carAudio
        case .headphones, nil:
            let name = name.lowercased()
            self = Self.nameHints.first { name.contains($0.0) }?.1 ?? .headphones
        }
    }

    public var symbol: String {
        switch self {
        case .airpods: "airpods"
        case .airpodsGen3: "airpods.gen3"
        case .airpodsPro: "airpodspro"
        case .airpodsMax: "airpodsmax"
        case .beatsHeadphones: "beats.headphones"
        case .beatsEarphones: "beats.earphones"
        case .powerbeats: "beats.powerbeats"
        case .powerbeatsPro: "beats.powerbeatspro"
        case .beatsStudioBuds: "beats.studiobuds"
        case .beatsFitPro: "beats.fitpro"
        case .headphones: "headphones"
        case .speaker: "hifispeaker.fill"
        case .carAudio: "car.fill"
        }
    }

    public var hasTwoBuds: Bool {
        switch self {
        case .airpods, .airpodsGen3, .airpodsPro, .powerbeatsPro, .beatsStudioBuds, .beatsFitPro: true
        case .airpodsMax, .beatsHeadphones, .beatsEarphones, .powerbeats, .headphones, .speaker, .carAudio: false
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

public enum BluetoothAccess: String, CaseIterable, Codable, Sendable {
    case notDetermined = "not-determined"
    case restricted, denied, allowed

    public init(_ authorization: CBManagerAuthorization) {
        switch authorization {
        case .allowedAlways: self = .allowed
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        default: self = .denied
        }
    }
}

public enum HeadphonesWatch: Equatable, Sendable {
    case off
    case listenForAccess
    case watch

    public init(enabled: Bool, access: BluetoothAccess) {
        guard enabled else {
            self = .off
            return
        }
        self = access == .allowed ? .watch : .listenForAccess
    }
}

public struct HeadphonesAccess: Equatable, Sendable {
    public private(set) var enabled = false
    public private(set) var access: BluetoothAccess

    public init(access: BluetoothAccess) {
        self.access = access
    }

    public var watch: HeadphonesWatch { HeadphonesWatch(enabled: enabled, access: access) }

    public mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public mutating func accessChanged(to access: BluetoothAccess) {
        self.access = access
    }
}

public struct BluetoothReport: Equatable, Sendable {
    public let name: String
    public let vendorID: Int?
    public let productID: Int?
    public let battery: HeadphonesBattery

    static let appleVendorID = 0x004C

    public var appleProductID: Int? { vendorID == Self.appleVendorID ? productID : nil }

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
        vendorID = (payload["device_vendorID"] as? String).flatMap(Self.hex)
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
        let number = text.split(separator: " ").first.map(String.init) ?? ""
        return Int(number.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16)
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

    public let showFor: TimeInterval
    private let clock: any T3Clock
    private var hideTask: Task<Void, Never>?

    public init(showFor: TimeInterval = 4, clock: any T3Clock = LiveClock()) {
        self.showFor = showFor
        self.clock = clock
    }

    public func show(_ connect: HeadphonesConnect) {
        current = connect
        hideTask?.cancel()
        let hideAt = clock.now + showFor
        hideTask = Task { [weak self, clock, id = connect.id] in
            try? await clock.sleep(until: hideAt)
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

@MainActor
public final class StartupHeadphones {
    public let window: TimeInterval
    private let clock: any T3Clock
    private var addresses: Set<String> = []
    private(set) var clearTask: Task<Void, Never>?

    public init(window: TimeInterval = 2, clock: any T3Clock = LiveClock()) {
        self.window = window
        self.clock = clock
    }

    public func begin(alreadyConnected: Set<String>) {
        end()
        addresses = alreadyConnected
        let clearAt = clock.now + window
        clearTask = Task { [weak self, clock] in
            try? await clock.sleep(until: clearAt)
            guard !Task.isCancelled else { return }
            self?.addresses = []
        }
    }

    public func end() {
        clearTask?.cancel()
        clearTask = nil
        addresses = []
    }

    public func isNewConnect(forgetting address: String) -> Bool {
        addresses.remove(address) == nil
    }
}
