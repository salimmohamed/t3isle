import XCTest
@testable import T3IsleCore

final class LoginItemTests: XCTestCase {
    func testReleaseReregistersAnEnabledLoginItemAtEveryLaunch() {
        XCTAssertEqual(LoginItemPlan(isDebug: false, status: .enabled).atLaunch, .register)
    }

    func testReleaseLeavesItemsTheUserNeverEnabledOrSwitchedOff() {
        XCTAssertEqual(LoginItemPlan(isDebug: false, status: .notRegistered).atLaunch, .none)
        XCTAssertEqual(LoginItemPlan(isDebug: false, status: .notFound).atLaunch, .none)
        XCTAssertEqual(LoginItemPlan(isDebug: false, status: .requiresApproval).atLaunch, .none)
    }

    func testDebugRemovesItsOwnLoginItemAndNeverRegisters() {
        XCTAssertEqual(LoginItemPlan(isDebug: true, status: .enabled).atLaunch, .unregister)
        XCTAssertEqual(LoginItemPlan(isDebug: true, status: .requiresApproval).atLaunch, .unregister)
        XCTAssertEqual(LoginItemPlan(isDebug: true, status: .notRegistered).atLaunch, .none)
        XCTAssertEqual(LoginItemPlan(isDebug: true, status: .notRegistered).toggled(on: true), .none)
    }

    func testToggleRegistersOrUnregistersInRelease() {
        let plan = LoginItemPlan(isDebug: false, status: .notRegistered)
        XCTAssertEqual(plan.toggled(on: true), .register)
        XCTAssertEqual(plan.toggled(on: false), .unregister)
    }

    func testToggleStaysOnWhileMacOSWaitsForApproval() {
        let plan = LoginItemPlan(isDebug: false, status: .requiresApproval)
        XCTAssertTrue(plan.isOn)
        XCTAssertEqual(plan.note, .switchedOffInSettings)
    }

    func testDebugShowsWhyTheToggleIsUnavailable() {
        let plan = LoginItemPlan(isDebug: true, status: .enabled)
        XCTAssertFalse(plan.isOn)
        XCTAssertEqual(plan.note, .unavailableInDebug)
    }

    func testEnabledReleaseItemSaysHowToRemoveOtherEntries() {
        XCTAssertEqual(LoginItemPlan(isDebug: false, status: .enabled).note, .removeOtherEntries)
    }

    func testReleaseItemThatIsOffNeedsNoNote() {
        XCTAssertNil(LoginItemPlan(isDebug: false, status: .notRegistered).note)
    }
}
