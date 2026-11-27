import XCTest
@testable import T3IsleCore

final class AccessibilityTrustTests: XCTestCase {
    func testUncheckedBeforeTheFirstRead() {
        XCTAssertEqual(AccessibilityTrust().guidance, .unchecked)
        XCTAssertFalse(AccessibilityTrust().guidance.showsReAddHint)
    }

    func testDeniedReadShowsTheReAddHint() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.denied))
        XCTAssertEqual(trust.guidance, .denied)
        XCTAssertTrue(trust.guidance.showsReAddHint)
    }

    func testTrustedReadShowsNoHint() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.trusted))
        XCTAssertEqual(trust.guidance, .trusted)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testUnreachableHelperShowsNoHint() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.unreachable))
        XCTAssertEqual(trust.guidance, .unreachable)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testUnreachableHelperDropsAnEarlierDenial() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.denied))
        trust.checked(tickets.reading(.unreachable))
        XCTAssertEqual(trust.guidance, .unreachable)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testDeniedAgainWhenAGrantStopsMatching() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.trusted))
        trust.checked(tickets.reading(.denied))
        XCTAssertEqual(trust.guidance, .denied)
    }

    func testTrustedOnceTheGrantMatchesAgain() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        trust.checked(tickets.reading(.denied))
        trust.checked(tickets.reading(.trusted))
        XCTAssertEqual(trust.guidance, .trusted)
    }

    func testGrantedMapsToTrustedOrDenied() {
        XCTAssertEqual(AccessibilityRead(granted: true), .trusted)
        XCTAssertEqual(AccessibilityRead(granted: false), .denied)
    }

    func testUnreachableNoticeOffersNoRequest() {
        XCTAssertFalse(AccessibilityGuidance.unreachable.offersRequest)
        XCTAssertTrue(AccessibilityGuidance.denied.offersRequest)
        XCTAssertTrue(AccessibilityGuidance.unchecked.offersRequest)
    }

    func testCancelledEnableDoesNothingEvenWhenDenied() {
        XCTAssertNil(HUDReplacementEnable(read: .denied, cancelled: true))
        XCTAssertNil(HUDReplacementEnable(read: .trusted, cancelled: true))
    }

    func testEnableRequestsAccessAndTurnsOffOnlyAfterADenial() {
        XCTAssertEqual(HUDReplacementEnable(read: .trusted, cancelled: false), .startInterceptor)
        XCTAssertEqual(HUDReplacementEnable(read: .denied, cancelled: false), .requestAccessAndTurnOff)
    }

    func testUnreachableReadKeepsTheSavedSwitch() {
        XCTAssertEqual(HUDReplacementEnable(read: .unreachable, cancelled: false), .keepSaved)
    }

    func testAGoodReadAfterAnUnreachableOneCountsAsAChange() {
        var changes = AccessibilityReadChanges()
        var tickets = AccessibilityReadTickets()
        XCTAssertTrue(changes.record(tickets.reading(.trusted)))
        XCTAssertFalse(changes.record(tickets.reading(.trusted)))
        XCTAssertTrue(changes.record(tickets.reading(.unreachable)))
        XCTAssertFalse(changes.record(tickets.reading(.unreachable)))
        XCTAssertTrue(changes.record(tickets.reading(.trusted)))
    }

    func testAnOlderReadThatAnswersLastIsNotAChange() {
        var changes = AccessibilityReadChanges()
        var tickets = AccessibilityReadTickets()
        let older = tickets.reading(.denied)
        let newer = tickets.reading(.trusted)

        XCTAssertTrue(changes.record(newer))
        XCTAssertFalse(changes.record(older))
        XCTAssertEqual(changes.last, newer)
    }

    func testAnOlderReadThatAnswersLastLeavesTheNewerGuidance() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        let older = tickets.reading(.unreachable)
        let newer = tickets.reading(.trusted)

        XCTAssertTrue(trust.checked(newer))
        XCTAssertFalse(trust.checked(older))
        XCTAssertEqual(trust.guidance, .trusted)
    }

    func testTheSameReadArrivingTwiceLandsOnce() {
        var trust = AccessibilityTrust()
        var tickets = AccessibilityReadTickets()
        let reading = tickets.reading(.denied)

        XCTAssertTrue(trust.checked(reading))
        XCTAssertFalse(trust.checked(reading))
    }

    func testDeniedReadTurnsOffASwitchThatIsOn() {
        XCTAssertEqual(HUDReplacementTrustChange(read: .denied, isOn: true), .turnOff)
        XCTAssertEqual(HUDReplacementTrustChange(read: .trusted, isOn: true), .startInterceptor)
        XCTAssertNil(HUDReplacementTrustChange(read: .unreachable, isOn: true))
        XCTAssertNil(HUDReplacementTrustChange(read: nil, isOn: true))
    }

    func testTrustChangesLeaveASwitchThatIsOffAlone() {
        for read in AccessibilityRead.allCases {
            XCTAssertNil(HUDReplacementTrustChange(read: read, isOn: false))
        }
    }

    @MainActor
    func testUnreachableReadIsRetriedOnItsOwnWithABackoff() async {
        let clock = TestClock()
        let (reads, continuation) = AsyncStream<Void>.makeStream()
        var landedReads = reads.makeAsyncIterator()
        let retry = UnreachableReadRetry(clock: clock) { continuation.yield() }

        for wait: TimeInterval in [1, 2, 4, 8, 16, 30, 30] {
            retry.landed(.unreachable)
            await clock.waitForSleepers()
            XCTAssertEqual(clock.deadlines, [clock.now + wait])
            clock.advance(by: wait)
            await landedReads.next()
        }
    }

    @MainActor
    func testAReachableReadStopsTheRetryAndResetsTheBackoff() async {
        let clock = TestClock()
        let (reads, continuation) = AsyncStream<Void>.makeStream()
        var landedReads = reads.makeAsyncIterator()
        let retry = UnreachableReadRetry(clock: clock) { continuation.yield() }
        for wait: TimeInterval in [1, 2] {
            retry.landed(.unreachable)
            await clock.waitForSleepers()
            clock.advance(by: wait)
            await landedReads.next()
        }
        retry.landed(.unreachable)
        await clock.waitForSleepers()

        retry.landed(.denied)

        XCTAssertEqual(clock.deadlines, [])
        retry.landed(.unreachable)
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 1])
    }
}

private extension AccessibilityReadTickets {
    mutating func reading(_ read: AccessibilityRead) -> AccessibilityReading {
        AccessibilityReading(read: read, ticket: issue())
    }
}
