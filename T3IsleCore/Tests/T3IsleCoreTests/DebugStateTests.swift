import XCTest
@testable import T3IsleCore

final class DebugStateTests: XCTestCase {
    private let monitor = DebugState.HeadphonesMonitor(bluetooth: .denied, status: .listening)

    private func state() throws -> DebugState {
        let t3 = try JSONDecoder().decode(DebugState.T3.self, from: Fixture.data("debug-state-question.json"))
        return DebugState(notch: .closed, tab: .t3, settingsOpen: false, closedActivity: .t3, headphones: nil,
                          notchViewModels: 1, headphonesMonitor: monitor, hudAccessibility: .untrusted, t3: t3)
    }

    func testEncodingIsByteStableAndRoundTrips() throws {
        let first = try DebugState.encoded(try state())
        let second = try DebugState.encoded(try state())
        XCTAssertEqual(first, second)
        XCTAssertEqual(try JSONDecoder().decode(DebugState.self, from: first), try state())
    }

    func testEveryKeyIsPresentEvenWhenEmpty() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: DebugState.encoded(try state())) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["notch", "tab", "settingsOpen", "closedActivity", "headphones", "notchViewModels",
                                          "headphonesMonitor", "hudAccessibility", "t3"])
        XCTAssertTrue(object["headphones"] is NSNull)
        XCTAssertEqual(object["closedActivity"] as? String, "t3")
        let t3 = try XCTUnwrap(object["t3"] as? [String: Any])
        XCTAssertEqual(Set(t3.keys), ["enabled", "source", "replay", "connection", "presence", "threads", "prompts", "agents",
                                      "banner", "providers"])
        XCTAssertTrue(t3["banner"] is NSNull)
    }

    func testAppFieldsUseFlatNames() throws {
        let headphones = HeadphonesConnect(address: "debug", name: "AirPods Pro", kind: .airpodsPro)
        let state = DebugState(notch: .open, tab: .shelf, settingsOpen: true, closedActivity: .headphones(headphones),
                               headphones: headphones, notchViewModels: 2,
                               headphonesMonitor: DebugState.HeadphonesMonitor(bluetooth: .notDetermined, status: .watching),
                               hudAccessibility: .stale, t3: try state().t3)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: DebugState.encoded(state)) as? [String: Any])
        XCTAssertEqual(object["notch"] as? String, "open")
        XCTAssertEqual(object["tab"] as? String, "shelf")
        XCTAssertEqual(object["settingsOpen"] as? Bool, true)
        XCTAssertEqual(object["closedActivity"] as? String, "headphones")
        XCTAssertEqual(object["headphones"] as? [String: String], ["name": "AirPods Pro", "kind": "airpodsPro"])
        XCTAssertEqual(object["notchViewModels"] as? Int, 2)
        XCTAssertEqual(object["headphonesMonitor"] as? [String: String], ["bluetooth": "not-determined", "status": "watching"])
        XCTAssertEqual(object["hudAccessibility"] as? String, "stale")
    }
}

final class DebugEventLogTests: XCTestCase {
    func testEncodesOneEventPerLine() throws {
        let time = try XCTUnwrap(WireDate.parse("2026-11-16T10:00:00.123Z"))
        let event = DebugEvent(time: time, name: "command.ran",
                               attributes: ["input": "t3isle-debug://replay/question?n=4", "command": "replay question"])
        XCTAssertEqual(event.line, #"{"time":"2026-11-16T10:00:00.123Z","event":"command.ran","#
                       + #""attributes":{"command":"replay question","input":"t3isle-debug://replay/question?n=4"}}"#)
        XCTAssertEqual(DebugEvent(time: time, name: "notch.opened").line,
                       #"{"time":"2026-11-16T10:00:00.123Z","event":"notch.opened","attributes":{}}"#)
    }

    func testEscapesValuesIntoValidJSON() throws {
        let message = "Usage: \"replay\"\nnext line"
        let line = DebugEvent(time: Scenario.anchor, name: "command.failed", attributes: ["message": message]).line
        XCTAssertFalse(line.contains("\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual((object["attributes"] as? [String: String])?["message"], message)
    }

    func testAppendsAndRotatesALargeLogOnOpen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("debug-event-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = StateFolders.isolated(in: root)
        try folders.createLogs()
        let old = Data(String(repeating: "x", count: 64).utf8)
        try old.write(to: folders.eventLog)

        let rotating = DebugEventLog(folders: folders, rotateAtBytes: 32)
        rotating.record("first", at: Date(timeIntervalSince1970: 0))
        rotating.flush()
        XCTAssertEqual(try Data(contentsOf: folders.rotatedEventLog), old)

        let appending = DebugEventLog(folders: folders, rotateAtBytes: 5_000_000)
        appending.record("second", ["n": "2"], at: Date(timeIntervalSince1970: 0))
        appending.flush()
        let lines = try String(contentsOf: folders.eventLog, encoding: .utf8).split(separator: "\n")
        let events = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])["event"] as? String }
        XCTAssertEqual(events, ["first", "second"])
    }

    func testALateWriteFromAnEarlierProcessKeepsTheNewProcessLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("debug-event-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = StateFolders.isolated(in: root)

        let quitting = DebugEventLog(folders: folders)
        quitting.flush()
        let launched = DebugEventLog(folders: folders)
        launched.record("app.launched", at: Date(timeIntervalSince1970: 0))
        launched.flush()
        quitting.record("app.terminating", at: Date(timeIntervalSince1970: 0))
        quitting.flush()

        let lines = try String(contentsOf: folders.eventLog, encoding: .utf8).split(separator: "\n")
        let events = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])["event"] as? String }
        XCTAssertEqual(events, ["app.launched", "app.terminating"])
    }
}
