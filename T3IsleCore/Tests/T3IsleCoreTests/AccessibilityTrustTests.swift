import XCTest
@testable import T3IsleCore

final class AccessibilityTrustTests: XCTestCase {
    func testUntrustedBeforeTheFirstCheckEvenAfterAnEarlierRequest() {
        XCTAssertEqual(AccessibilityTrust(asked: false).guidance, .untrusted)
        XCTAssertEqual(AccessibilityTrust(asked: true).guidance, .untrusted)
    }

    func testUntrustedWhenNeverAsked() {
        var trust = AccessibilityTrust(asked: false)
        trust.checked(trusted: false)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .untrusted)
    }

    func testStaysUntrustedWhileTheUserIsAwayAnswering() {
        var trust = AccessibilityTrust(asked: false)
        trust.checked(trusted: false)
        trust.requested()
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .untrusted)
        XCTAssertTrue(trust.awaitingReturn)
    }

    func testLikelyStaleWhenTheUserComesBackStillUntrusted() {
        var trust = AccessibilityTrust(asked: false)
        trust.requested()
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
        XCTAssertTrue(trust.asked)
    }

    func testOnboardingRequestBeforeAnyCheckIsStaleAfterAnUntrustedReturn() {
        var trust = AccessibilityTrust(asked: false)
        trust.requested()
        XCTAssertEqual(trust.guidance, .untrusted)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testLikelyStaleAfterARelaunchThatFollowedARequest() {
        var trust = AccessibilityTrust(asked: true)
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testTrustedWhenTheGrantLandsWhileAway() {
        var trust = AccessibilityTrust(asked: false)
        trust.requested()
        trust.checked(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
        XCTAssertFalse(trust.awaitingReturn)
    }

    func testTrustClearsTheRequestSoALaterRevokeIsNotStale() {
        var trust = AccessibilityTrust(asked: false)
        trust.requested()
        trust.appBecameActive(trusted: false)
        trust.appBecameActive(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
        XCTAssertFalse(trust.asked)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .untrusted)
    }

    func testAskingAgainFromStaleWaitsForTheNextReturn() {
        var trust = AccessibilityTrust(asked: true)
        trust.checked(trusted: false)
        trust.requested()
        XCTAssertEqual(trust.guidance, .untrusted)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testForgettingTheRequestLeavesPlainUntrusted() {
        var trust = AccessibilityTrust(asked: true)
        trust.requested()
        trust.forgetRequest()
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .untrusted)
        XCTAssertFalse(trust.asked)
        XCTAssertFalse(trust.awaitingReturn)
    }
}
