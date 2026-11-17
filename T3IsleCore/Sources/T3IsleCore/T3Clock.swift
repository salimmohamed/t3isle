import Foundation

public protocol T3Clock: Sendable {
    var now: Date { get }
    func sleep(until deadline: Date) async throws
}

public struct LiveClock: T3Clock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(now))))
    }
}
