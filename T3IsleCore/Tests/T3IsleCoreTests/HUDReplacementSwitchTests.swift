import Observation
import XCTest
@testable import T3IsleCore

@MainActor
final class HUDReplacementSwitchTests: XCTestCase {
    func testUncheckedBeforeTheFirstRead() {
        let rig = Rig()
        XCTAssertEqual(rig.hudSwitch.guidance, .unchecked)
        XCTAssertFalse(rig.hudSwitch.guidance.showsReAddHint)
    }

    func testGuidanceFollowsTheNewestRead() {
        let rig = Rig()
        let expected: [(AccessibilityRead, AccessibilityGuidance, Bool)] = [
            (.denied, .denied, true),
            (.unreachable, .unreachable, false),
            (.trusted, .trusted, false),
            (.denied, .denied, true),
        ]
        for (read, guidance, showsHint) in expected {
            rig.hudSwitch.landed(rig.trust.reading(read))
            XCTAssertEqual(rig.hudSwitch.guidance, guidance)
            XCTAssertEqual(rig.hudSwitch.guidance.showsReAddHint, showsHint)
        }
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

    func testAnOlderReadThatAnswersLastIsDropped() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .trusted)
        let older = rig.trust.reading(.denied)
        let newer = rig.trust.reading(.trusted)

        rig.hudSwitch.landed(newer)
        rig.hudSwitch.landed(older)

        XCTAssertEqual(rig.hudSwitch.guidance, .trusted)
        XCTAssertEqual(rig.outputs, [.startInterceptor])
    }

    func testAnotherUnreachableReadLeavesTheArmedRetryAlone() async {
        let rig = Rig()
        rig.hudSwitch.hudPane(isOpen: true)
        await rig.answer(1, .unreachable)
        XCTAssertEqual(rig.hudSwitch.nextRetry, rig.clock.now + 1)

        rig.hudSwitch.landed(rig.trust.reading(.unreachable))
        rig.hudSwitch.landed(rig.trust.reading(.unreachable))

        XCTAssertEqual(rig.hudSwitch.nextRetry, rig.clock.now + 1)
    }

    func testTheSameReadAgainLeavesGuidanceObserversAlone() {
        let rig = Rig()
        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        let changed = Flag()
        withObservationTracking {
            _ = rig.hudSwitch.guidance
        } onChange: {
            changed.raise()
        }

        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        XCTAssertFalse(changed.isRaised)

        rig.hudSwitch.landed(rig.trust.reading(.denied))
        XCTAssertTrue(changed.isRaised)
    }

    func testSwitchingOnWhileTrustedStartsTheInterceptor() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .trusted)
        XCTAssertEqual(rig.outputs, [.startInterceptor])
    }

    func testSwitchingOnWhileDeniedRequestsAccessAndTurnsOff() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .denied)
        XCTAssertEqual(rig.outputs, [.requestAccess, .turnOff])
    }

    func testSwitchingOnWhileUnreachableKeepsTheSavedSwitch() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .unreachable)
        XCTAssertEqual(rig.outputs, [])
        XCTAssertEqual(rig.hudSwitch.nextRetry, rig.clock.now + 1)
    }

    func testSwitchingOnDecidesOnTheNewestRead() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.trust.arrived(1)
        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        XCTAssertEqual(rig.outputs, [])

        await rig.answer(1, .denied)

        XCTAssertEqual(rig.outputs, [.startInterceptor])
        XCTAssertEqual(rig.hudSwitch.guidance, .trusted)
    }

    func testATrustChangeWhileOnFollowsTheRead() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .unreachable)

        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        XCTAssertEqual(rig.outputs, [.startInterceptor])

        rig.hudSwitch.landed(rig.trust.reading(.denied))
        XCTAssertEqual(rig.outputs, [.startInterceptor, .turnOff])

        rig.hudSwitch.landed(rig.trust.reading(.trusted))
        XCTAssertEqual(rig.outputs, [.startInterceptor, .turnOff])
    }

    func testTrustChangesLeaveASwitchThatIsOffAlone() {
        let rig = Rig()
        for read in AccessibilityRead.allCases + AccessibilityRead.allCases {
            rig.hudSwitch.landed(rig.trust.reading(read))
        }
        XCTAssertEqual(rig.outputs, [])
    }

    func testSwitchingOffStopsTheInterceptor() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .trusted)
        rig.hudSwitch.switched(isOn: false)
        XCTAssertEqual(rig.outputs, [.startInterceptor, .stopInterceptor])
    }

    func testOnOffOnDuringOneSlowDeniedReadRequestsAccessOnce() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        rig.hudSwitch.switched(isOn: false)
        rig.hudSwitch.switched(isOn: true)

        await rig.answer(1, .denied)
        XCTAssertEqual(rig.outputs, [.stopInterceptor])
        await rig.answer(2, .denied)

        XCTAssertEqual(rig.outputs, [.stopInterceptor, .requestAccess, .turnOff])
    }

    func testOnOffOnDecidesOnTheReadAfterTheLastSwitchOn() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        rig.hudSwitch.switched(isOn: false)
        rig.hudSwitch.switched(isOn: true)

        await rig.answer(1, .denied)
        await rig.answer(2, .trusted)

        XCTAssertEqual(rig.outputs, [.stopInterceptor, .startInterceptor])
    }

    func testOnOffOnOffEndsOffWithoutARequest() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        rig.hudSwitch.switched(isOn: false)
        rig.hudSwitch.switched(isOn: true)
        rig.hudSwitch.switched(isOn: false)

        await rig.answer(1, .denied)
        await rig.answer(2, .denied)

        XCTAssertEqual(rig.outputs, [.stopInterceptor, .stopInterceptor])
    }

    func testUnreachableReadIsRetriedWithABackoffWhileTheSwitchIsOn() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .unreachable)

        for (index, wait) in [1, 2, 4, 8, 16, 30, 30].enumerated() {
            await rig.retryArmed()
            XCTAssertEqual(rig.clock.deadlines, [rig.clock.now + TimeInterval(wait)])
            await rig.advance(by: TimeInterval(wait))
            await rig.answer(index + 2, .unreachable)
        }
        XCTAssertEqual(rig.outputs, [])
    }

    func testAReachableReadStopsTheRetryAndResetsTheBackoff() async {
        let rig = Rig()
        rig.hudSwitch.hudPane(isOpen: true)
        await rig.answer(1, .unreachable)
        await rig.retryArmed()
        await rig.advance(by: 1)
        await rig.answer(2, .unreachable)
        await rig.retryArmed()

        rig.hudSwitch.landed(rig.trust.reading(.trusted))

        XCTAssertEqual(rig.clock.deadlines, [])
        XCTAssertNil(rig.hudSwitch.nextRetry)
        rig.hudSwitch.check()
        await rig.answer(3, .unreachable)
        XCTAssertEqual(rig.hudSwitch.nextRetry, rig.clock.now + 1)
    }

    func testAnUnreachableReadIsNotRetriedWhileTheSwitchIsOffAndThePaneIsClosed() async {
        let rig = Rig()
        rig.hudSwitch.check()
        await rig.answer(1, .unreachable)
        XCTAssertNil(rig.hudSwitch.nextRetry)
        XCTAssertEqual(rig.clock.deadlines, [])
    }

    func testTheRetryRunsWhileTheHUDPaneIsOpen() async {
        let rig = Rig()
        rig.hudSwitch.hudPane(isOpen: true)
        await rig.answer(1, .unreachable)
        await rig.retryArmed()
        await rig.advance(by: 1)
        await rig.answer(2, .unreachable)
        await rig.retryArmed()
        XCTAssertEqual(rig.clock.deadlines, [rig.clock.now + 2])

        rig.hudSwitch.hudPane(isOpen: false)

        XCTAssertEqual(rig.clock.deadlines, [])
        XCTAssertNil(rig.hudSwitch.nextRetry)
    }

    func testTurningTheSwitchOffStopsTheRetryWhileThePaneIsClosed() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .unreachable)
        await rig.retryArmed()

        rig.hudSwitch.switched(isOn: false)

        XCTAssertEqual(rig.clock.deadlines, [])
        XCTAssertNil(rig.hudSwitch.nextRetry)
    }

    func testClosingThePaneKeepsTheRetryWhileTheSwitchIsOn() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        await rig.answer(1, .unreachable)
        rig.hudSwitch.hudPane(isOpen: true)
        await rig.answer(2, .unreachable)
        await rig.retryArmed()

        rig.hudSwitch.hudPane(isOpen: false)

        XCTAssertEqual(rig.clock.deadlines, [rig.clock.now + 1])
    }

    func testAnUnreachableReadAfterSwitchingOffIsNotRetried() async {
        let rig = Rig()
        rig.hudSwitch.switched(isOn: true)
        rig.hudSwitch.switched(isOn: false)
        await rig.answer(1, .unreachable)
        XCTAssertNil(rig.hudSwitch.nextRetry)
    }

    func testIsSettledOnceEveryReadHasLanded() async {
        let rig = Rig()
        XCTAssertTrue(rig.hudSwitch.isSettled)
        rig.hudSwitch.check()
        XCTAssertFalse(rig.hudSwitch.isSettled)
        await rig.answer(1, .trusted)
        XCTAssertTrue(rig.hudSwitch.isSettled)
    }
}

@MainActor
private final class Rig {
    let clock = TestClock()
    let trust = TrustReads()
    let hudSwitch: HUDReplacementSwitch
    private(set) var outputs: [HUDReplacementSwitch.Output] = []

    init() {
        hudSwitch = HUDReplacementSwitch(clock: clock) { [trust] in await trust.read() }
        hudSwitch.apply = { [unowned self] in outputs.append($0) }
    }

    func answer(_ number: Int, _ read: AccessibilityRead, file: StaticString = #filePath, line: UInt = #line) async {
        guard hudSwitch.isReading(number) else {
            return XCTFail("Read \(number) never started", file: file, line: line)
        }
        await trust.answer(number, read)
        await hudSwitch.readFinished(number)
    }

    func retryArmed(file: StaticString = #filePath, line: UInt = #line) async {
        guard hudSwitch.nextRetry != nil else {
            return XCTFail("No retry is armed", file: file, line: line)
        }
        await clock.waitForSleepers()
    }

    func advance(by seconds: TimeInterval) async {
        clock.advance(by: seconds)
        await hudSwitch.retryRan()
    }
}

@MainActor
private final class TrustReads {
    private var tickets = AccessibilityReadTickets()
    private var callTickets: [AccessibilityReadTicket] = []
    private var waiting: [Int: CheckedContinuation<AccessibilityReading, Never>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]

    func reading(_ read: AccessibilityRead) -> AccessibilityReading {
        AccessibilityReading(read: read, ticket: tickets.issue())
    }

    func read() async -> AccessibilityReading {
        callTickets.append(tickets.issue())
        let number = callTickets.count
        return await withCheckedContinuation { continuation in
            waiting[number] = continuation
            arrivals.removeValue(forKey: number)?.resume()
        }
    }

    func arrived(_ number: Int) async {
        guard number > callTickets.count else { return }
        await withCheckedContinuation { arrivals[number] = $0 }
    }

    func answer(_ number: Int, _ read: AccessibilityRead) async {
        await arrived(number)
        let ticket = callTickets[number - 1]
        waiting.removeValue(forKey: number)?.resume(returning: AccessibilityReading(read: read, ticket: ticket))
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool { lock.withLock { raised } }

    func raise() {
        lock.withLock { raised = true }
    }
}
