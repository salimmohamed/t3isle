import XCTest
@testable import T3IsleCore

final class TokenStoreTests: XCTestCase {
    private var folder: URL!
    private var store: FileTokenStore!
    private let token = StoredToken(token: "secret", expiresAt: Date(timeIntervalSince1970: 2_000_000_000), sessionId: "s1")

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("T3 Isle")
        store = FileTokenStore(file: folder.appendingPathComponent("session.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    func testRoundTrip() throws {
        try store.save(token)
        XCTAssertEqual(store.load(), token)
    }

    func testSaveReplacesEarlierToken() throws {
        try store.save(token)
        let newer = StoredToken(token: "newer", expiresAt: Date(timeIntervalSince1970: 2_100_000_000))
        try store.save(newer)
        XCTAssertEqual(store.load(), newer)
        XCTAssertEqual(try permissions(of: file), 0o600)
    }

    func testFileIsOwnerOnly() throws {
        try store.save(token)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(try permissions(of: folder), 0o700)
    }

    func testSaveTightensLooseFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try store.save(token)
        XCTAssertEqual(try permissions(of: folder), 0o700)
    }

    func testSaveTightensLooseFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o644])
        try store.save(token)
        XCTAssertEqual(try permissions(of: file), 0o600)
        XCTAssertEqual(store.load(), token)
    }

    func testMissingFileLoadsNothing() {
        XCTAssertNil(store.load())
    }

    func testCorruptFileLoadsNothing() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        XCTAssertNil(store.load())
    }

    func testClearRemovesFile() throws {
        try store.save(token)
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    private var file: URL { folder.appendingPathComponent("session.json") }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as! NSNumber).intValue
    }
}
