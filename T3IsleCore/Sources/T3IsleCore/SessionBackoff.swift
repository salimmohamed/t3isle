import Foundation

struct SessionBackoff: Sendable {
    static let rejectionsUntilWait = 2
    static let firstWait: TimeInterval = 60
    static let longestWait: TimeInterval = 300

    private(set) var rejections = 0
    private(set) var retryAt: Date?

    func allows(at now: Date) -> Bool {
        retryAt.map { now >= $0 } ?? true
    }

    mutating func rejected(at now: Date) {
        guard allows(at: now) else { return }
        rejections += 1
        retryAt = Self.wait(after: rejections).map { now + $0 }
    }

    mutating func accepted() {
        rejections = 0
        retryAt = nil
    }

    static func wait(after rejections: Int) -> TimeInterval? {
        let doublings = rejections - rejectionsUntilWait
        guard doublings >= 0 else { return nil }
        return min(firstWait * pow(2, Double(doublings)), longestWait)
    }
}
