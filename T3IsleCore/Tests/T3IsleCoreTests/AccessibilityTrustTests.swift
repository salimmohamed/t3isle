import XCTest
@testable import T3IsleCore

final class AccessibilityTrustTests: XCTestCase {
    func testUncheckedBeforeTheFirstRead() {
        XCTAssertEqual(AccessibilityTrust().guidance, .unchecked)
        XCTAssertFalse(AccessibilityTrust().guidance.showsReAddHint)
    }

    func testDeniedReadShowsTheReAddHint() {
        var trust = AccessibilityTrust()
        trust.checked(.denied)
        XCTAssertEqual(trust.guidance, .denied)
        XCTAssertTrue(trust.guidance.showsReAddHint)
    }

    func testTrustedReadShowsNoHint() {
        var trust = AccessibilityTrust()
        trust.checked(.trusted)
        XCTAssertEqual(trust.guidance, .trusted)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testUnreachableHelperShowsNoHint() {
        var trust = AccessibilityTrust()
        trust.checked(.unreachable)
        XCTAssertEqual(trust.guidance, .unreachable)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testUnreachableHelperDropsAnEarlierDenial() {
        var trust = AccessibilityTrust()
        trust.checked(.denied)
        trust.checked(.unreachable)
        XCTAssertEqual(trust.guidance, .unreachable)
        XCTAssertFalse(trust.guidance.showsReAddHint)
    }

    func testDeniedAgainWhenAGrantStopsMatching() {
        var trust = AccessibilityTrust()
        trust.checked(.trusted)
        trust.checked(.denied)
        XCTAssertEqual(trust.guidance, .denied)
    }

    func testTrustedOnceTheGrantMatchesAgain() {
        var trust = AccessibilityTrust()
        trust.checked(.denied)
        trust.checked(.trusted)
        XCTAssertEqual(trust.guidance, .trusted)
    }

    func testGrantedMapsOnlyAnsweredReads() {
        XCTAssertEqual(AccessibilityRead(granted: true), .trusted)
        XCTAssertEqual(AccessibilityRead(granted: false), .denied)
        XCTAssertEqual(AccessibilityRead.allCases.map(\.granted), [true, false, nil])
    }
}
