import XCTest
@testable import T3IsleCore

final class AccessibilityTrustTests: XCTestCase {
    func testUntrustedBeforeTheFirstCheck() {
        XCTAssertEqual(AccessibilityTrust().guidance, .untrusted)
    }

    func testStaleOnTheFirstUntrustedReadWithoutAnyRequest() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testStaleWhenTheAppComesBackUntrustedWithoutAnyRequest() {
        var trust = AccessibilityTrust()
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testStaysUntrustedWhileTheUserIsAwayAnswering() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: false)
        trust.requested()
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .untrusted)
        XCTAssertTrue(trust.awaitingReturn)
    }

    func testStaleWhenTheUserComesBackStillUntrusted() {
        var trust = AccessibilityTrust()
        trust.requested()
        XCTAssertEqual(trust.guidance, .untrusted)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
        XCTAssertFalse(trust.awaitingReturn)
    }

    func testTrustedWhenTheGrantLandsWhileAway() {
        var trust = AccessibilityTrust()
        trust.requested()
        trust.checked(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
        XCTAssertFalse(trust.awaitingReturn)
    }

    func testStaleAgainWhenAGrantStopsMatching() {
        var trust = AccessibilityTrust()
        trust.appBecameActive(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testAskingAgainFromStaleWaitsForTheNextReturn() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: false)
        trust.requested()
        XCTAssertEqual(trust.guidance, .untrusted)
        trust.appBecameActive(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }
}
