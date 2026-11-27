import XCTest
@testable import T3IsleCore

@MainActor
final class PomodoroTests: XCTestCase {
    func testIdleTimerShowsAFullFocusBlock() {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertFalse(timer.isActive)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.countdown(at: clock.now), "25:00")
    }

    func testFocusRunsIntoABreakAndThenStops() async {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        timer.start()
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isRunning)
        let focusEnd = clock.now + PomodoroTimer.focusLength
        XCTAssertEqual(timer.endsAt, focusEnd)
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [focusEnd])

        clock.advance(by: 60)
        XCTAssertEqual(timer.countdown(at: clock.now), "24:00")
        clock.advance(by: 0.5)
        XCTAssertEqual(timer.countdown(at: clock.now), "24:00")

        clock.advance(by: PomodoroTimer.focusLength - 60.5)
        await until(timer) { timer.phase == .rest }
        let breakEnd = focusEnd + PomodoroTimer.breakLength
        XCTAssertEqual(timer.endsAt, breakEnd)
        XCTAssertEqual(timer.countdown(at: clock.now), "5:00")
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [breakEnd])

        clock.advance(by: PomodoroTimer.breakLength)
        await until(timer) { timer.phase == .idle }
        XCTAssertNil(timer.endsAt)
        XCTAssertEqual(timer.countdown(at: clock.now), "25:00")
    }

    func testPauseKeepsTheTimeLeftAndResumeCarriesOn() async {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        timer.start()
        await clock.waitForSleepers()
        clock.advance(by: 10 * 60)
        let running = timer.phaseEnd

        timer.pause()
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isActive)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.pausedLeft, 15 * 60)
        await running?.value
        XCTAssertTrue(clock.deadlines.isEmpty)

        clock.advance(by: 60 * 60)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.countdown(at: clock.now), "15:00")

        timer.start()
        XCTAssertTrue(timer.isRunning)
        XCTAssertNil(timer.pausedLeft)
        await clock.waitForSleepers()
        XCTAssertEqual(clock.deadlines, [clock.now + 15 * 60])
        clock.advance(by: 15 * 60)
        await until(timer) { timer.phase == .rest }
        XCTAssertEqual(timer.endsAt, clock.now + PomodoroTimer.breakLength)
    }

    func testPausingTheBreakResumesTheBreak() async {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        timer.start()
        await clock.waitForSleepers()
        clock.advance(by: PomodoroTimer.focusLength)
        await until(timer) { timer.phase == .rest }
        clock.advance(by: 60)
        timer.pause()
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.countdown(at: clock.now), "4:00")
        timer.start()
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.endsAt, clock.now + 4 * 60)
    }

    func testResetGoesBackToIdleAndCancelsThePhaseEnd() async {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        timer.start()
        await clock.waitForSleepers()
        clock.advance(by: 5 * 60)
        let running = timer.phaseEnd

        timer.reset()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(timer.endsAt)
        XCTAssertNil(timer.pausedLeft)
        await running?.value
        XCTAssertTrue(clock.deadlines.isEmpty)

        clock.advance(by: PomodoroTimer.focusLength)
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.countdown(at: clock.now), "25:00")
    }

    func testResetWhilePausedAndPauseWhileIdleDoNothingOdd() {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        timer.pause()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(timer.pausedLeft)
        timer.start()
        timer.pause()
        timer.reset()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(timer.pausedLeft)
        timer.start()
        XCTAssertEqual(timer.endsAt, clock.now + PomodoroTimer.focusLength)
    }

    func testDebugStateNamesThePhaseAndWhetherItRuns() {
        let clock = TestClock()
        let timer = PomodoroTimer(clock: clock)
        XCTAssertEqual(timer.debugState(enabled: false), DebugState.Pomodoro(enabled: false, phase: .idle, running: false))
        timer.start()
        timer.pause()
        XCTAssertEqual(timer.debugState(enabled: true), DebugState.Pomodoro(enabled: true, phase: .focus, running: false))
    }
}
