import XCTest
@testable import T3IsleCore

@MainActor
final class FakePasteboard: ClipboardSource {
    private(set) var changeCount = 0
    private var contents: (types: [String], text: String?) = ([], nil)
    private(set) var reads = 0
    var whileReadingText: (() -> Void)?

    var types: [String] {
        reads += 1
        return contents.types
    }

    func string() -> String? {
        reads += 1
        let text = contents.text
        whileReadingText?()
        whileReadingText = nil
        return text
    }

    func mark(_ type: String) {
        contents.types.append(type)
    }

    func setString(_ string: String) {
        copy(string)
    }

    func copy(_ text: String?, types: [String] = ["public.utf8-plain-text"]) {
        changeCount += 1
        contents = (types, text)
    }
}

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private let clock = TestClock()
    private let pasteboard = FakePasteboard()
    private lazy var history = ClipboardHistory(pasteboard: pasteboard, clock: clock)

    private func turnOn() async {
        history.setEnabled(true)
        await clock.waitForSleepers()
    }

    private func poll() async {
        clock.advance(by: ClipboardHistory.pollInterval)
        await clock.waitForSleepers()
    }

    private func copyAndPoll(_ texts: String...) async {
        for text in texts {
            pasteboard.copy(text)
            await poll()
        }
    }

    func testRecordsNewCopiesNewestFirst() async {
        await turnOn()
        await copyAndPoll("one", "two", "three")
        XCTAssertEqual(history.items, ["three", "two", "one"])
    }

    func testKeepsOnlyTheLastTwentyCopies() async {
        await turnOn()
        for index in 1...25 { await copyAndPoll("copy \(index)") }
        XCTAssertEqual(history.items.count, ClipboardHistory.limit)
        XCTAssertEqual(history.items.first, "copy 25")
        XCTAssertEqual(history.items.last, "copy 6")
    }

    func testCopyingAgainMovesTheItemToTheTop() async {
        await turnOn()
        await copyAndPoll("one", "two", "three", "one")
        XCTAssertEqual(history.items, ["one", "three", "two"])
    }

    func testSkipsConcealedAndTransientCopies() async {
        await turnOn()
        await copyAndPoll("visible")
        pasteboard.copy("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        await poll()
        pasteboard.copy("one-time code", types: ["org.nspasteboard.TransientType", "public.utf8-plain-text"])
        await poll()
        XCTAssertEqual(history.items, ["visible"])
    }

    func testSkipsTextThatTurnsConcealedWhileItIsRead() async {
        await turnOn()
        pasteboard.copy("hunter2")
        pasteboard.whileReadingText = { [pasteboard] in pasteboard.mark("org.nspasteboard.ConcealedType") }
        await poll()
        await poll()
        XCTAssertTrue(history.items.isEmpty)
    }

    func testRereadsWhenANewCopyLandsWhileTheTextIsRead() async {
        await turnOn()
        pasteboard.copy("plain copy")
        pasteboard.whileReadingText = { [pasteboard] in
            pasteboard.copy("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        }
        await poll()
        await poll()
        XCTAssertTrue(history.items.isEmpty)
        await copyAndPoll("next")
        XCTAssertEqual(history.items, ["next"])
    }

    func testSkipsCopiesWithoutTextAndBlankText() async {
        await turnOn()
        pasteboard.copy(nil, types: ["public.png"])
        await poll()
        await copyAndPoll(" \n\t")
        XCTAssertTrue(history.items.isEmpty)
    }

    func testReadsNothingUntilTurnedOnAndAfterTurnedOff() async {
        pasteboard.copy("before")
        clock.advance(by: 60)
        XCTAssertEqual(pasteboard.reads, 0)
        XCTAssertNil(history.polling)
        XCTAssertTrue(clock.deadlines.isEmpty)

        await turnOn()
        XCTAssertTrue(history.isWatching)
        await poll()
        XCTAssertTrue(history.items.isEmpty, "What was on the pasteboard before turning on is not a new copy")
        await copyAndPoll("during")
        XCTAssertEqual(history.items, ["during"])

        let polling = history.polling
        history.setEnabled(false)
        await polling?.value
        XCTAssertFalse(history.isWatching)
        XCTAssertTrue(history.items.isEmpty)
        let readsWhenOff = pasteboard.reads
        pasteboard.copy("after")
        clock.advance(by: 60)
        XCTAssertEqual(pasteboard.reads, readsWhenOff)
        XCTAssertTrue(clock.deadlines.isEmpty)
    }

    func testOnlyReadsThePasteboardContentsWhenItChanged() async {
        await turnOn()
        await copyAndPoll("one")
        let reads = pasteboard.reads
        await poll()
        await poll()
        XCTAssertEqual(pasteboard.reads, reads)
    }

    func testTurningOnTwiceKeepsOnePoll() async {
        await turnOn()
        let polling = history.polling
        history.setEnabled(true)
        XCTAssertTrue(history.polling == polling)
        XCTAssertEqual(clock.deadlines.count, 1)
    }

    func testCopyingAnItemBackPutsItOnThePasteboardAndAtTheTop() async {
        await turnOn()
        await copyAndPoll("one", "two")
        history.copy("one")
        XCTAssertEqual(pasteboard.string(), "one")
        XCTAssertEqual(history.items, ["one", "two"])
        await poll()
        XCTAssertEqual(history.items, ["one", "two"])
    }

    func testPreviewPutsALongCopyOnOneLine() {
        XCTAssertEqual(ClipboardHistory.preview("  first line\n\n   second\r\nthird  "), "first line second third")
        XCTAssertEqual(ClipboardHistory.preview("plain"), "plain")
        XCTAssertEqual(ClipboardHistory.preview(String(repeating: "a", count: 10_000)).count, ClipboardHistory.previewLength)
    }

    func testDebugStateCountsItemsAndWhetherItWatches() async {
        XCTAssertEqual(history.debugState(enabled: false), DebugState.Clipboard(enabled: false, watching: false, items: 0))
        await turnOn()
        await copyAndPoll("one", "two")
        XCTAssertEqual(history.debugState(enabled: true), DebugState.Clipboard(enabled: true, watching: true, items: 2))
    }
}
