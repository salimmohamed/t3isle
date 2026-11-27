import Foundation

struct SessionBackoff: Sendable {
    static let rejectionsBeforeWaiting = 2
    static let firstWait: TimeInterval = 60
    static let longestWait: TimeInterval = 1800

    private(set) var rejections = 0
    private(set) var retryAt: Date?

    func allows(at now: Date) -> Bool {
        retryAt.map { now >= $0 } ?? true
    }

    mutating func rejected(at now: Date) {
        rejections += 1
        retryAt = Self.wait(after: rejections).map { now + $0 }
    }

    mutating func accepted() {
        rejections = 0
        retryAt = nil
    }

    static func wait(after rejections: Int) -> TimeInterval? {
        let doublings = rejections - rejectionsBeforeWaiting
        guard doublings >= 0 else { return nil }
        return min(firstWait * pow(2, Double(min(doublings, 16))), longestWait)
    }
}
