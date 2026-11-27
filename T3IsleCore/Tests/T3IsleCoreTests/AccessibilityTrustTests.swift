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
        XCTAssertTrue(changes.record(.trusted))
        XCTAssertFalse(changes.record(.trusted))
        XCTAssertTrue(changes.record(.unreachable))
        XCTAssertFalse(changes.record(.unreachable))
        XCTAssertTrue(changes.record(.trusted))
    }
}
