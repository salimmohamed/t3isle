import CoreBluetooth
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

    func testConnectedIdleShowsTheGlanceOnlyWhenNothingElseIsLive() {
        XCTAssertEqual(ClosedActivity.resolve(t3: .idle, headphones: nil, nowPlaying: false), .t3)
        XCTAssertEqual(ClosedActivity.resolve(t3: .idle, headphones: nil, nowPlaying: true), .nowPlaying)
        XCTAssertEqual(ClosedActivity.resolve(t3: .idle, headphones: pods, nowPlaying: false), .headphones(pods))
    }

    func testBluetoothAccessReadsEachAuthorization() {
        let authorizations: [CBManagerAuthorization] = [.notDetermined, .restricted, .denied, .allowedAlways]
        XCTAssertEqual(authorizations.map(BluetoothAccess.init), [.notDetermined, .restricted, .denied, .allowed])
    }

    func testEnabledWithoutAccessListensForAGrant() {
        for access in [BluetoothAccess.notDetermined, .restricted, .denied] {
            XCTAssertEqual(HeadphonesWatch(enabled: true, access: access), .listenForAccess)
        }
    }

    func testWatchesOnlyWhenEnabledAndAllowed() {
        XCTAssertEqual(HeadphonesWatch(enabled: true, access: .allowed), .watch)
        for access in BluetoothAccess.allCases {
            XCTAssertEqual(HeadphonesWatch(enabled: false, access: access), .off)
        }
    }

    func testStartsOffUntilTheSettingIsOn() {
        var state = HeadphonesAccess(access: .allowed)
        XCTAssertEqual(state.watch, .off)
        state.setEnabled(true)
        XCTAssertEqual(state.watch, .watch)
    }

    func testGrantAfterDenialStartsWatching() {
        var state = HeadphonesAccess(access: .denied)
        state.setEnabled(true)
        XCTAssertEqual(state.watch, .listenForAccess)
        state.accessChanged(to: .allowed)
        XCTAssertEqual(state.watch, .watch)
    }

    func testGrantFromThePromptStartsWatching() {
        var state = HeadphonesAccess(access: .notDetermined)
        state.setEnabled(true)
        XCTAssertEqual(state.watch, .listenForAccess)
        state.accessChanged(to: .allowed)
        XCTAssertEqual(state.watch, .watch)
    }

    func testRevokingAccessStopsWatchingAndKeepsListening() {
        var state = HeadphonesAccess(access: .allowed)
        state.setEnabled(true)
        state.accessChanged(to: .denied)
        XCTAssertEqual(state.watch, .listenForAccess)
        state.accessChanged(to: .allowed)
        XCTAssertEqual(state.watch, .watch)
    }

    func testTurningTheSettingOffStopsEverything() {
        var state = HeadphonesAccess(access: .allowed)
        state.setEnabled(true)
        state.setEnabled(false)
        XCTAssertEqual(state.watch, .off)
        state.accessChanged(to: .denied)
        XCTAssertEqual(state.watch, .off)
    }

    func testReportReadsTheLowerBudLevelByAddress() throws {
        let report = try XCTUnwrap(BluetoothReport.find(address: "68-3e-c0-00-00-02", inSystemProfilerJSON: fixture()))
        XCTAssertEqual(report.name, "Studio AirPods Pro")
        XCTAssertEqual(report.battery, HeadphonesBattery(left: 100, right: 95))
        XCTAssertEqual(report.battery.level, 95)
        XCTAssertEqual(report.appleProductID, 0x2024)
        XCTAssertEqual(HeadphonesKind(appleProductID: report.appleProductID, classOfDevice: nil, name: "Renamed buds"), .airpodsPro)
    }

    func testReportReadsSingleBatteryHeadphones() throws {
        let report = try XCTUnwrap(BluetoothReport.find(address: "10:20:30:00:00:03", inSystemProfilerJSON: fixture()))
        XCTAssertEqual(report.battery, HeadphonesBattery(single: 42))
        XCTAssertEqual(report.battery.level, 42)
        XCTAssertEqual(report.productID, 0xFFFF)
        XCTAssertNil(report.appleProductID)
        XCTAssertEqual(HeadphonesKind(appleProductID: report.appleProductID, classOfDevice: nil, name: report.name), .headphones)
    }

    func testReportWithoutBatteryIsEmptyAndUnknownAddressIsMissing() throws {
        let speaker = try XCTUnwrap(BluetoothReport.find(address: "10-20-30-00-00-04", inSystemProfilerJSON: fixture()))
        XCTAssertTrue(speaker.battery.isEmpty)
        XCTAssertNil(BluetoothReport.find(address: "ff-ff-ff-ff-ff-ff", inSystemProfilerJSON: try fixture()))
        XCTAssertNil(BluetoothReport.find(address: "68-3e-c0-00-00-02", inSystemProfilerJSON: Data("nope".utf8)))
    }

    func testKindComesFromAppleProductThenDeviceClassThenName() {
        let headphonesClass: UInt32 = 0x240418
        let headsetClass: UInt32 = 0x240404
        let loudspeakerClass: UInt32 = 0x240414
        let portableAudioClass: UInt32 = 0x24041C
        let hifiClass: UInt32 = 0x240428
        let carAudioClass: UInt32 = 0x240420
        let handsFreeClass: UInt32 = 0x340408
        let phoneClass: UInt32 = 0x5A020C
        let cases: [(Int?, UInt32?, String, HeadphonesKind)] = [
            (0x2002, nil, "Buds", .airpods),
            (0x200F, headphonesClass, "Buds", .airpods),
            (0x2013, headphonesClass, "AirPods", .airpodsGen3),
            (0x2019, nil, "AirPods", .airpodsGen3),
            (0x201B, nil, "AirPods", .airpodsGen3),
            (0x200E, nil, "AirPods", .airpodsPro),
            (0x2014, nil, "AirPods", .airpodsPro),
            (0x2024, headphonesClass, "Speaker", .airpodsPro),
            (0x2027, nil, "AirPods", .airpodsPro),
            (0x200A, nil, "AirPods", .airpodsMax),
            (0x201F, loudspeakerClass, "AirPods", .airpodsMax),
            (0x2006, nil, "Solo3", .beatsHeadphones),
            (0x2009, nil, "Studio3", .beatsHeadphones),
            (0x200C, nil, "Solo Pro", .beatsHeadphones),
            (0x2017, nil, "Studio Pro", .beatsHeadphones),
            (0x2025, nil, "Solo 4", .beatsHeadphones),
            (0x2005, nil, "BeatsX", .beatsEarphones),
            (0x2010, nil, "Flex", .beatsEarphones),
            (0x2003, nil, "PB3", .powerbeats),
            (0x200D, nil, "PB4", .powerbeats),
            (0x200B, nil, "PB Pro", .powerbeatsPro),
            (0x201D, nil, "PB Pro 2", .powerbeatsPro),
            (0x2011, nil, "Buds", .beatsStudioBuds),
            (0x2016, nil, "Buds+", .beatsStudioBuds),
            (0x2026, nil, "Solo Buds", .beatsStudioBuds),
            (0x2012, nil, "Fit", .beatsFitPro),
            (0xFFFF, loudspeakerClass, "Boom", .speaker),
            (nil, loudspeakerClass, "AirPods", .speaker),
            (nil, portableAudioClass, "Pocket", .speaker),
            (nil, hifiClass, "Living Room", .speaker),
            (nil, carAudioClass, "Beats", .carAudio),
            (nil, handsFreeClass, "Sync", .headphones),
            (nil, headphonesClass, "Sam's AirPods Max", .airpodsMax),
            (nil, headsetClass, "Sam's AirPods Pro", .airpodsPro),
            (nil, nil, "AirPods", .airpods),
            (nil, nil, "Powerbeats Pro", .powerbeatsPro),
            (nil, nil, "Powerbeats", .powerbeats),
            (nil, nil, "Beats Studio Buds", .beatsStudioBuds),
            (nil, nil, "Beats Solo Buds", .beatsStudioBuds),
            (nil, nil, "Beats Fit Pro", .beatsFitPro),
            (nil, nil, "Beats Flex", .beatsEarphones),
            (nil, nil, "BeatsX", .beatsEarphones),
            (nil, nil, "Beats Studio Pro", .beatsHeadphones),
            (nil, headphonesClass, "WH-1000XM5", .headphones),
            (nil, phoneClass, "Car Phone", .headphones),
            (nil, nil, "Desk Headset", .headphones),
        ]
        for (productID, classOfDevice, name, expected) in cases {
            XCTAssertEqual(HeadphonesKind(appleProductID: productID, classOfDevice: classOfDevice, name: name), expected,
                           "\(String(describing: productID)) \(String(describing: classOfDevice)) \(name)")
        }
    }

    func testEveryKindHasItsOwnSymbol() {
        let symbols: [(HeadphonesKind, String)] = [
            (.airpods, "airpods"), (.airpodsGen3, "airpods.gen3"), (.airpodsPro, "airpodspro"), (.airpodsMax, "airpodsmax"),
            (.beatsHeadphones, "beats.headphones"), (.beatsEarphones, "beats.earphones"), (.powerbeats, "beats.powerbeats"),
            (.powerbeatsPro, "beats.powerbeatspro"), (.beatsStudioBuds, "beats.studiobuds"), (.beatsFitPro, "beats.fitpro"),
            (.headphones, "headphones"), (.speaker, "hifispeaker.fill"), (.carAudio, "car.fill"),
        ]
        for (kind, symbol) in symbols {
            XCTAssertEqual(kind.symbol, symbol, "\(kind)")
        }
        XCTAssertEqual(Set(symbols.map(\.1)).count, symbols.count)
    }

    func testDebugDeviceClassesMapBackToTheirKind() {
        let expected: [BluetoothAudioClass: HeadphonesKind] = [.headphones: .headphones, .speaker: .speaker, .car: .carAudio]
        for device in BluetoothAudioClass.allCases {
            XCTAssertEqual(BluetoothAudioClass(classOfDevice: device.classOfDevice), device)
            XCTAssertEqual(HeadphonesKind(appleProductID: nil, classOfDevice: device.classOfDevice, name: "Device"), expected[device])
        }
    }

    func testVendorIDKeepsItsHexWhenProfilerAddsTheCompanyName() {
        XCTAssertEqual(BluetoothReport.hex("0x004C (Apple)"), 0x004C)
        XCTAssertEqual(BluetoothReport.hex("0x2024"), 0x2024)
    }

    @MainActor
    func testPopupHidesItselfAfterItsDuration() async throws {
        let clock = TestClock()
        let popup = HeadphonesPopup(showFor: 4, clock: clock)
        popup.show(pods)
        XCTAssertEqual(popup.current, pods)
        popup.update(battery: HeadphonesBattery(left: 70, right: 72), for: pods.id)
        XCTAssertEqual(popup.current?.battery.level, 70)
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 4])
        clock.advance(by: 4)
        await until(popup) { popup.current == nil }
    }

    @MainActor
    func testNewerConnectKeepsItsOwnFullDuration() async throws {
        let clock = TestClock()
        let popup = HeadphonesPopup(showFor: 4, clock: clock)
        popup.show(pods)
        await clock.waitForSleepers()
        clock.advance(by: 3)
        let headset = HeadphonesConnect(address: "10-20-30-00-00-03", name: "Desk Headset", kind: .headphones)
        popup.show(headset)
        popup.update(battery: HeadphonesBattery(left: 1), for: pods.id)
        XCTAssertEqual(popup.current, headset)
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 4])
        clock.advance(by: 4)
        await until(popup) { popup.current == nil }
    }

    @MainActor
    func testQuickToggleKeepsTheNewStartupListForItsWholeWindow() async {
        let clock = TestClock()
        let startup = StartupHeadphones(window: 2, clock: clock)
        startup.begin(alreadyConnected: [pods.address])
        let firstWindow = startup.clearTask
        await clock.waitForSleepers()
        clock.advance(by: 1)
        startup.end()
        startup.begin(alreadyConnected: [pods.address])
        await firstWindow?.value
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 2])
        clock.advance(by: 1.5)
        XCTAssertFalse(startup.isNewConnect(forgetting: pods.address))
        XCTAssertTrue(startup.isNewConnect(forgetting: pods.address))
    }

    @MainActor
    func testStartupListClearsWhenItsWindowEnds() async {
        let clock = TestClock()
        let startup = StartupHeadphones(window: 2, clock: clock)
        startup.begin(alreadyConnected: [pods.address])
        await clock.waitForSleepers()
        clock.advance(by: 2)
        await startup.clearTask?.value
        XCTAssertTrue(startup.isNewConnect(forgetting: pods.address))
    }

    @MainActor
    func testTurningOffForgetsTheStartupList() async {
        let startup = StartupHeadphones(window: 2, clock: TestClock())
        startup.begin(alreadyConnected: [pods.address])
        startup.end()
        XCTAssertTrue(startup.isNewConnect(forgetting: pods.address))
    }

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "bluetooth-profiler", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
