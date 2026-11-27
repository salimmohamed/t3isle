import XCTest
@testable import T3IsleCore

final class EventTapSlotTests: XCTestCase {
    func testASecondStartWhileTheFirstAwaitsTrustTakesOverTheSlot() throws {
        var slot = EventTapSlot<Int>()
        let first = try XCTUnwrap(slot.claim())
        let second = try XCTUnwrap(slot.claim())
        XCTAssertNotEqual(first, second)
    }

    func testOnlyTheLastOfTwoOverlappingStartsMakesATap() throws {
        var slot = EventTapSlot<Int>()
        var made = 0
        let first = try XCTUnwrap(slot.claim())
        let second = try XCTUnwrap(slot.claim())
        XCTAssertNil(slot.fill(first) { made += 1; return made })
        slot.fill(second) { made += 1; return made }
        XCTAssertEqual(made, 1)
        XCTAssertEqual(slot.tap, 1)
        XCTAssertNil(slot.claim())
    }

    func testAStaleDeniedReadAfterATrustedOneLeavesTheTap() throws {
        var slot = EventTapSlot<Int>()
        let staleDenied = try XCTUnwrap(slot.claim())
        let trusted = try XCTUnwrap(slot.claim())
        slot.fill(trusted) { 7 }
        XCTAssertNil(slot.fill(staleDenied) { nil })
        XCTAssertEqual(slot.tap, 7)
    }

    func testAStartThatArrivesWhileADeniedReadIsPendingStillMakesATap() throws {
        var slot = EventTapSlot<Int>()
        let staleDenied = try XCTUnwrap(slot.claim())
        let trusted = try XCTUnwrap(slot.claim())
        XCTAssertNil(slot.fill(staleDenied) { nil })
        slot.fill(trusted) { 7 }
        XCTAssertEqual(slot.tap, 7)
    }

    func testStopDuringTwoOverlappingStartsKeepsBothFromMakingATap() throws {
        var slot = EventTapSlot<Int>()
        let first = try XCTUnwrap(slot.claim())
        let second = try XCTUnwrap(slot.claim())
        XCTAssertNil(slot.empty())
        var made = false
        XCTAssertNil(slot.fill(first) { made = true; return 1 })
        XCTAssertNil(slot.fill(second) { made = true; return 2 })
        XCTAssertFalse(made)
        XCTAssertNil(slot.tap)
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
