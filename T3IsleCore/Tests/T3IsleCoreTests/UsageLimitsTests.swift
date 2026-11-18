import XCTest
@testable import T3IsleCore

final class UsageLimitsTests: XCTestCase {
    func testParsesWindowsFromProviderCache() throws {
        let data = try Fixture.data("provider-claude.json")
        let limits = try XCTUnwrap(UsageLimitsReader.parse(data, id: "claudeAgent", previous: []))
        XCTAssertEqual(limits.name, "Claude")
        XCTAssertEqual(limits.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(limits.windows.first?.usedPercent, 22)
        XCTAssertNil(limits.note)
    }

    func testSkipsUnsupportedProviders() throws {
        let data = try Fixture.data("provider-unsupported.json")
        XCTAssertNil(UsageLimitsReader.parse(data, id: "opencode", previous: []))
    }

    func testKeepsLastWindowsWhenCheckFails() throws {
        let previous = ProviderLimits(id: "codex", name: "Codex", accentHex: nil, checkedAt: nil,
                                      windows: [LimitWindow(id: "w", kind: "session", label: "Session", usedPercent: 40, resetsAt: nil)],
                                      note: nil)
        let data = try Fixture.data("provider-failed.json")
        let limits = try XCTUnwrap(UsageLimitsReader.parse(data, id: "codex", previous: [previous]))
        XCTAssertEqual(limits.windows, previous.windows)
        XCTAssertEqual(limits.note, "Rate limit check timed out")
    }

    func testRemainingIsFullAfterReset() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = LimitWindow(id: "w", kind: "session", label: "S", usedPercent: 90, resetsAt: now.addingTimeInterval(-1))
        XCTAssertEqual(window.remaining(at: now), 100)
    }

    func testTightestPrefersRequestedKind() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = ProviderLimits(id: "c", name: "C", accentHex: nil, checkedAt: nil, windows: [
            LimitWindow(id: "s", kind: "session", label: "S", usedPercent: 10, resetsAt: nil),
            LimitWindow(id: "w", kind: "weekly", label: "W", usedPercent: 80, resetsAt: nil),
        ], note: nil)
        XCTAssertEqual(provider.tightest(at: now, kind: "session")?.id, "s")
        XCTAssertEqual(provider.tightest(at: now)?.id, "w")
    }

    func testOrdersClaudeThenCodex() {
        let make = { (id: String, name: String) in
            ProviderLimits(id: id, name: name, accentHex: nil, checkedAt: nil, windows: [], note: nil)
        }
        let ordered = UsageLimitsReader.ordered([make("zed", "A"), make("codex", "Codex"), make("claudeAgent", "Claude")])
        XCTAssertEqual(ordered.map(\.id), ["claudeAgent", "codex", "zed"])
    }

    func testRuntimeOriginMustBeLocal() {
        XCTAssertEqual(T3Home.origin(fromRuntime: Data(#"{"origin":"http://127.0.0.1:3773"}"#.utf8))?.port, 3773)
        XCTAssertNil(T3Home.origin(fromRuntime: Data(#"{"origin":"http://10.0.0.5:3773"}"#.utf8)))
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}
