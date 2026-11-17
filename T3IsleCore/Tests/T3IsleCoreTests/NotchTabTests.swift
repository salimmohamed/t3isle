import XCTest
@testable import T3IsleCore

final class NotchTabTests: XCTestCase {
    func testChosenTabOpensWhateverTabWasLastShown() {
        for current in NotchTab.allCases {
            XCTAssertEqual(OpeningTab.home.tab(current: current, t3Ready: true, shelfFirst: false), .home)
            XCTAssertEqual(OpeningTab.t3.tab(current: current, t3Ready: true, shelfFirst: false), .t3)
            XCTAssertEqual(OpeningTab.shelf.tab(current: current, t3Ready: true, shelfFirst: false), .shelf)
        }
    }

    func testLastUsedTabKeepsTheCurrentTab() {
        for current in NotchTab.allCases {
            XCTAssertEqual(OpeningTab.last.tab(current: current, t3Ready: true, shelfFirst: false), current)
        }
    }

    func testT3FallsBackToHomeWithoutThreads() {
        XCTAssertEqual(OpeningTab.t3.tab(current: .shelf, t3Ready: false, shelfFirst: false), .home)
        XCTAssertEqual(OpeningTab.last.tab(current: .t3, t3Ready: false, shelfFirst: false), .home)
    }

    func testShelfItemsOpenTheShelfWhateverTheChoice() {
        for choice in OpeningTab.allCases {
            XCTAssertEqual(choice.tab(current: .home, t3Ready: true, shelfFirst: true), .shelf)
        }
    }
}
