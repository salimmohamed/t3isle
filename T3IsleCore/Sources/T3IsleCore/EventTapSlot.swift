public struct EventTapSlot<Tap> {
    public struct Claim: Equatable, Sendable {
        fileprivate let id: Int
    }

    private var lastClaim = 0
    private var pending: Claim?
    public private(set) var tap: Tap?

    public init() {}

    public mutating func claim() -> Claim? {
        guard tap == nil else { return nil }
        lastClaim += 1
        let claim = Claim(id: lastClaim)
        pending = claim
        return claim
    }

    @discardableResult
    public mutating func fill(_ claim: Claim, with make: () -> Tap?) -> Tap? {
        guard pending == claim else { return nil }
        pending = nil
        tap = make()
        return tap
    }

    public mutating func empty() -> Tap? {
        pending = nil
        defer { tap = nil }
        return tap
    }
}
