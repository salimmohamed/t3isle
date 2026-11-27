import XCTest
@testable import T3IsleCore

final class AccessibilityTrustTests: XCTestCase {
    func testUntrustedBeforeTheFirstCheck() {
        XCTAssertEqual(AccessibilityTrust().guidance, .untrusted)
    }

    func testStaleOnTheFirstUntrustedRead() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testTrustedOnATrustedRead() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
    }

    func testStaleAgainWhenAGrantStopsMatching() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: true)
        trust.checked(trusted: false)
        XCTAssertEqual(trust.guidance, .stale)
    }

    func testTrustedOnceTheGrantMatchesAgain() {
        var trust = AccessibilityTrust()
        trust.checked(trusted: false)
        trust.checked(trusted: true)
        XCTAssertEqual(trust.guidance, .trusted)
    }
}
