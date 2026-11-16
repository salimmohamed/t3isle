import XCTest
@testable import T3IsleCore

final class LiveActivitiesTests: XCTestCase {
    private let pods = HeadphonesConnect(address: "68-3e-c0-00-00-02", name: "Studio AirPods Pro", kind: .airpodsPro)

    func testQuestionOrPlanDoneBeatsEveryOtherActivity() {
        XCTAssertEqual(ClosedActivity.resolve(t3: .alert, headphones: pods, nowPlaying: true), .t3)
    }

    func testFreshHeadphonesBeatMusicAndThreadFaces() {
        XCTAssertEqual(ClosedActivity.resolve(t3: .threads, headphones: pods, nowPlaying: true), .headphones(pods))
        XCTAssertEqual(ClosedActivity.resolve(t3: .none, headphones: pods, nowPlaying: false), .headphones(pods))
    }

    func testMusicBeatsThreadFacesWhenNothingNeedsYou() {
        XCTAssertEqual(ClosedActivity.resolve(t3: .threads, headphones: nil, nowPlaying: true), .nowPlaying)
        XCTAssertEqual(ClosedActivity.resolve(t3: .none, headphones: nil, nowPlaying: true), .nowPlaying)
    }

    func testThreadFacesShowWhenNothingElseIsLive() {
        XCTAssertEqual(ClosedActivity.resolve(t3: .threads, headphones: nil, nowPlaying: false), .t3)
        XCTAssertEqual(ClosedActivity.resolve(t3: .none, headphones: nil, nowPlaying: false), .none)
    }

    func testReportReadsTheLowerBudLevelByAddress() throws {
        let report = try XCTUnwrap(BluetoothReport.find(address: "68-3e-c0-00-00-02", inSystemProfilerJSON: fixture()))
        XCTAssertEqual(report.name, "Studio AirPods Pro")
        XCTAssertEqual(report.battery, HeadphonesBattery(left: 100, right: 95))
        XCTAssertEqual(report.battery.level, 95)
        XCTAssertEqual(HeadphonesKind(productID: report.productID, name: "Renamed buds"), .airpodsPro)
    }

    func testReportReadsSingleBatteryHeadphones() throws {
        let report = try XCTUnwrap(BluetoothReport.find(address: "10:20:30:00:00:03", inSystemProfilerJSON: fixture()))
        XCTAssertEqual(report.battery, HeadphonesBattery(single: 42))
        XCTAssertEqual(report.battery.level, 42)
        XCTAssertEqual(HeadphonesKind(productID: report.productID, name: report.name), .headphones)
    }

    func testReportWithoutBatteryIsEmptyAndUnknownAddressIsMissing() throws {
        let speaker = try XCTUnwrap(BluetoothReport.find(address: "10-20-30-00-00-04", inSystemProfilerJSON: fixture()))
        XCTAssertTrue(speaker.battery.isEmpty)
        XCTAssertNil(BluetoothReport.find(address: "ff-ff-ff-ff-ff-ff", inSystemProfilerJSON: try fixture()))
        XCTAssertNil(BluetoothReport.find(address: "68-3e-c0-00-00-02", inSystemProfilerJSON: Data("nope".utf8)))
    }

    func testKindFallsBackToNameWhenProductIsUnknown() {
        XCTAssertEqual(HeadphonesKind(productID: nil, name: "Sam's AirPods Max"), .airpodsMax)
        XCTAssertEqual(HeadphonesKind(productID: nil, name: "AirPods"), .airpods)
        XCTAssertEqual(HeadphonesKind(productID: nil, name: "Beats Flex"), .beats)
    }

    @MainActor
    func testPopupHidesItselfAfterItsDuration() async throws {
        let popup = HeadphonesPopup(showFor: .milliseconds(100))
        popup.show(pods)
        XCTAssertEqual(popup.current, pods)
        popup.update(battery: HeadphonesBattery(left: 70, right: 72), for: pods.id)
        XCTAssertEqual(popup.current?.battery.level, 70)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(popup.current)
    }

    @MainActor
    func testNewerConnectKeepsItsOwnFullDuration() async throws {
        let popup = HeadphonesPopup(showFor: .milliseconds(400))
        popup.show(pods)
        try await Task.sleep(for: .milliseconds(250))
        let headset = HeadphonesConnect(address: "10-20-30-00-00-03", name: "Desk Headset", kind: .headphones)
        popup.show(headset)
        popup.update(battery: HeadphonesBattery(left: 1), for: pods.id)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(popup.current, headset)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(popup.current)
    }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "bluetooth-profiler", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
