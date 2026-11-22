import XCTest
@testable import T3IsleCore

final class NotchTabTests: XCTestCase {
    func testChosenTabOpensWhateverTabWasLastShown() {
        for current in NotchTab.allCases {
            XCTAssertEqual(OpeningTab.home.tab(current: current, t3Ready: true, shelfFirst: false, barShown: true), .home)
            XCTAssertEqual(OpeningTab.t3.tab(current: current, t3Ready: true, shelfFirst: false, barShown: true), .t3)
            XCTAssertEqual(OpeningTab.shelf.tab(current: current, t3Ready: true, shelfFirst: false, barShown: true), .shelf)
        }
    }

    func testLastUsedTabKeepsTheCurrentTab() {
        for current in NotchTab.allCases {
            XCTAssertEqual(OpeningTab.last.tab(current: current, t3Ready: true, shelfFirst: false, barShown: true), current)
        }
    }

    func testT3FallsBackToHomeWithoutThreads() {
        XCTAssertEqual(OpeningTab.t3.tab(current: .shelf, t3Ready: false, shelfFirst: false, barShown: true), .home)
        XCTAssertEqual(OpeningTab.last.tab(current: .t3, t3Ready: false, shelfFirst: false, barShown: true), .home)
    }

    func testShelfItemsOpenTheShelfWhateverTheChoice() {
        for choice in OpeningTab.allCases {
            XCTAssertEqual(choice.tab(current: .home, t3Ready: true, shelfFirst: true, barShown: true), .shelf)
        }
    }

    func testHiddenTabBarAlwaysOpensHome() {
        for choice in OpeningTab.allCases {
            for current in NotchTab.allCases {
                XCTAssertEqual(choice.tab(current: current, t3Ready: false, shelfFirst: false, barShown: false), .home)
                XCTAssertEqual(choice.tab(current: current, t3Ready: true, shelfFirst: true, barShown: false), .home)
            }
        }
    }

    func testTabBarHidesOnlyWithoutT3AndWithoutShelfTabs() {
        XCTAssertFalse(NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: true, alwaysShowTabs: false))
        XCTAssertFalse(NotchTab.barShown(t3Enabled: false, shelfEnabled: false, shelfEmpty: false, alwaysShowTabs: true))
        XCTAssertTrue(NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: false, alwaysShowTabs: false))
        XCTAssertTrue(NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: true, alwaysShowTabs: true))
        XCTAssertTrue(NotchTab.barShown(t3Enabled: true, shelfEnabled: false, shelfEmpty: true, alwaysShowTabs: false))
    }

    func testOpenNotchLeavesAnyTabForHomeWhenTheBarHides() {
        for tab in NotchTab.allCases {
            XCTAssertEqual(tab.whileOpen(barShown: false), .home)
            XCTAssertEqual(tab.whileOpen(barShown: true), tab)
        }
    }

    func testRemovingTheLastShelfItemHidesTheBarAndLeavesShelf() {
        let before = NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: false, alwaysShowTabs: false)
        let after = NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: true, alwaysShowTabs: false)
        XCTAssertEqual(NotchTab.shelf.whileOpen(barShown: before), .shelf)
        XCTAssertEqual(NotchTab.shelf.whileOpen(barShown: after), .home)
    }

    func testEmptyShelfWithoutTabBarOpensHomeInsteadOfShelf() {
        let barShown = NotchTab.barShown(t3Enabled: false, shelfEnabled: true, shelfEmpty: true, alwaysShowTabs: false)
        XCTAssertEqual(OpeningTab.shelf.tab(current: .shelf, t3Ready: false, shelfFirst: false, barShown: barShown), .home)
        XCTAssertEqual(OpeningTab.last.tab(current: .shelf, t3Ready: false, shelfFirst: false, barShown: barShown), .home)
    }
}
