import ObjectiveC
import XCTest
@testable import T3IsleCore

final class StateFoldersTests: XCTestCase {
    private let library = URL(fileURLWithPath: "/Users/someone/Library", isDirectory: true)
    private let checkout = URL(fileURLWithPath: "/work/checkout", isDirectory: true)
    private var scratch: URL!
    private var originalStandard: IMP?

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        originalStandard = standardMethod.map(method_getImplementation)
    }

    override func tearDownWithError() throws {
        if let standardMethod, let originalStandard { method_setImplementation(standardMethod, originalStandard) }
        try? FileManager.default.removeItem(at: scratch)
    }

    func testInstalledAppKeepsTheShelfItInheritedFromBoringNotch() {
        let folders = StateFolders.standard(appName: "T3 Isle", library: library)
        XCTAssertNil(folders.root)
        XCTAssertEqual(folders.session.path, "/Users/someone/Library/Application Support/T3 Isle/session.json")
        XCTAssertEqual(folders.shelf.path, "/Users/someone/Library/Application Support/boringNotch/Shelf")
        XCTAssertEqual(folders.logs.path, "/Users/someone/Library/Logs/T3 Isle")
    }

    func testDebugAppKeepsEverythingInItsOwnFolders() {
        let folders = StateFolders.standard(appName: "T3 Isle Debug", library: library)
        XCTAssertNil(folders.root)
        XCTAssertNil(folders.defaults)
        XCTAssertEqual(folders.session.path, "/Users/someone/Library/Application Support/T3 Isle Debug/session.json")
        XCTAssertEqual(folders.shelf.path, "/Users/someone/Library/Application Support/T3 Isle Debug/Shelf")
        XCTAssertEqual(folders.eventLog.path, "/Users/someone/Library/Logs/T3 Isle Debug/events.ndjson")
        XCTAssertEqual(folders.rotatedEventLog.path, "/Users/someone/Library/Logs/T3 Isle Debug/events.1.ndjson")
        XCTAssertEqual(folders.stateFile.path, "/Users/someone/Library/Logs/T3 Isle Debug/state.json")
    }

    func testWithoutTheFlagTheAppUsesItsStandardFolders() {
        let folders = resolve(["/Applications/T3 Isle Debug.app/Contents/MacOS/T3 Isle", "--demo"])
        XCTAssertEqual(folders, StateFolders.standard(appName: "T3 Isle Debug", library: library))
    }

    func testAbsoluteStateDirHoldsEverything() throws {
        let folders = resolve(["app", "--demo", "--state-dir", "/work/state", "--debug", "open-notch"])
        XCTAssertEqual(try XCTUnwrap(folders.root).path, "/work/state")
        XCTAssertEqual(try XCTUnwrap(folders.defaults).path, "/work/state/defaults.plist")
        XCTAssertEqual(folders.session.path, "/work/state/session.json")
        XCTAssertEqual(folders.shelf.path, "/work/state/Shelf")
        XCTAssertEqual(folders.logs.path, "/work/state/logs")
        XCTAssertEqual(folders.eventLog.path, "/work/state/logs/events.ndjson")
        XCTAssertEqual(folders.rotatedEventLog.path, "/work/state/logs/events.1.ndjson")
        XCTAssertEqual(folders.stateFile.path, "/work/state/logs/state.json")
    }

    func testRelativeStateDirIsResolvedAgainstTheCurrentDirectory() throws {
        XCTAssertEqual(try XCTUnwrap(resolve(["app", "--state-dir", ".build/debug-state"]).root).path,
                       "/work/checkout/.build/debug-state")
        XCTAssertEqual(try XCTUnwrap(resolve(["app", "--state-dir", "../other/state"]).root).path,
                       "/work/other/state")
    }

    func testFlagWithoutAPathIsIgnored() {
        let standard = StateFolders.standard(appName: "T3 Isle Debug", library: library)
        XCTAssertEqual(resolve(["app", "--state-dir"]), standard)
        XCTAssertEqual(resolve(["app", "--state-dir", ""]), standard)
    }

    func testLaunchArgumentsCarryTheStateDirAcrossRelaunches() {
        XCTAssertEqual(StateFolders.isolated(in: URL(fileURLWithPath: "/work/state")).launchArguments,
                       ["--state-dir", "/work/state"])
        XCTAssertEqual(StateFolders.standard(appName: "T3 Isle Debug", library: library).launchArguments, [])
    }

    func testAppNameComesFromTheBundleDisplayName() throws {
        XCTAssertEqual(StateFolders.appName(bundle: try bundle(info: ["CFBundleDisplayName": "T3 Isle Debug"])),
                       "T3 Isle Debug")
        XCTAssertEqual(StateFolders.appName(bundle: try bundle(info: [:])), "T3 Isle")
    }

    func testIsolateMovesStandardDefaultsIntoTheStateDir() throws {
        let root = scratch.appendingPathComponent("nested/state", isDirectory: true)
        let folders = StateFolders.isolated(in: root)
        let key = "stateFoldersTest-\(UUID().uuidString)"

        try folders.isolate()
        UserDefaults.standard.set("isolated", forKey: key)
        UserDefaults.standard.synchronize()

        XCTAssertEqual(try permissions(of: root), 0o700)
        let stored = try XCTUnwrap(NSDictionary(contentsOf: try XCTUnwrap(folders.defaults)))
        XCTAssertEqual(stored[key] as? String, "isolated")

        if let standardMethod, let originalStandard { method_setImplementation(standardMethod, originalStandard) }
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    func testStandardFoldersLeaveStandardDefaultsAlone() throws {
        let before = UserDefaults.standard
        try StateFolders.standard(appName: "T3 Isle Debug", library: library).isolate()
        XCTAssertTrue(UserDefaults.standard === before)
    }

    private func resolve(_ arguments: [String]) -> StateFolders {
        StateFolders.resolve(arguments: arguments, currentDirectory: checkout, appName: "T3 Isle Debug", library: library)
    }

    private var standardMethod: Method? {
        class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))
    }

    private func bundle(info: [String: String]) throws -> Bundle {
        let root = scratch.appendingPathComponent("\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: root))
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
