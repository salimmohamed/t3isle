import Foundation

public enum ThreadMood: Int, Comparable, Sendable, CaseIterable {
    case needsYou, failed, replied, idle, working, waiting

    public var isBusy: Bool { self == .working || self == .waiting }

    public static func < (lhs: ThreadMood, rhs: ThreadMood) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .replied: "Replied"
        case .failed: "Failed"
        case .idle: "Idle"
        case .waiting: "Waiting"
        }
    }
}

public struct SeededRandom {
    private var state: UInt64

    public init(_ seed: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    public mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    public mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}
