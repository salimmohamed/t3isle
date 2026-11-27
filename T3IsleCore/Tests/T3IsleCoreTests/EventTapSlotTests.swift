import XCTest
@testable import T3IsleCore

final class EventTapSlotTests: XCTestCase {
    func testASecondStartWhileTheFirstAwaitsTrustClaimsNothing() {
        var slot = EventTapSlot<Int>()
        let first = slot.claim()
        XCTAssertNotNil(first)
        XCTAssertNil(slot.claim())
    }

    func testOnlyTheFirstOfTwoOverlappingStartsMakesATap() throws {
        var slot = EventTapSlot<Int>()
        var made = 0
        let first = try XCTUnwrap(slot.claim())
        let second = slot.claim()
        slot.fill(first) { made += 1; return made }
        if let second { slot.fill(second) { made += 1; return made } }
        XCTAssertEqual(made, 1)
        XCTAssertNil(slot.claim())
    }

    func testStopHandsBackTheTapItMade() throws {
        var slot = EventTapSlot<Int>()
        let claim = try XCTUnwrap(slot.claim())
        slot.fill(claim) { 7 }
        XCTAssertEqual(slot.empty(), 7)
        XCTAssertNil(slot.tap)
        XCTAssertNil(slot.empty())
    }

    func testStopDuringAStartKeepsThatStartFromMakingATap() throws {
        var slot = EventTapSlot<Int>()
        let claim = try XCTUnwrap(slot.claim())
        XCTAssertNil(slot.empty())
        var made = false
        XCTAssertNil(slot.fill(claim) { made = true; return 7 })
        XCTAssertFalse(made)
        XCTAssertNil(slot.tap)
    }

    func testAStartThatFindsNoTrustFreesTheSlot() throws {
        var slot = EventTapSlot<Int>()
        let claim = try XCTUnwrap(slot.claim())
        slot.fill(claim) { nil }
        XCTAssertNotNil(slot.claim())
    }
}
