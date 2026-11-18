#if DEBUG
import Foundation

public struct DebugPaths: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init(appName: String) {
        self.init(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true))
    }

    public var events: URL { directory.appendingPathComponent("events.ndjson") }
    public var rotatedEvents: URL { directory.appendingPathComponent("events.1.ndjson") }
    public var state: URL { directory.appendingPathComponent("state.json") }

    public func create() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

public struct DebugEvent: Equatable, Sendable {
    public let time: Date
    public let name: String
    public let attributes: [String: String]

    public init(time: Date, name: String, attributes: [String: String] = [:]) {
        self.time = time
        self.name = name
        self.attributes = attributes
    }

    public var line: String {
        "{\"time\":\(Self.json(WireDate.format(time))),\"event\":\(Self.json(name)),\"attributes\":\(Self.json(attributes))}"
    }

    private static func json<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

public final class DebugEventLog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.t3isle.debug-event-log")
    private var handle: FileHandle?

    public init(paths: DebugPaths, rotateAtBytes: Int = 5_000_000) {
        queue.async { [self] in handle = Self.open(paths, rotateAtBytes: rotateAtBytes) }
    }

    public func record(_ name: String, _ attributes: [String: String] = [:], at time: Date = Date()) {
        let line = Data((DebugEvent(time: time, name: name, attributes: attributes).line + "\n").utf8)
        queue.async { [self] in try? handle?.write(contentsOf: line) }
    }

    public func flush() {
        queue.sync {}
    }

    private static func open(_ paths: DebugPaths, rotateAtBytes: Int) -> FileHandle? {
        let files = FileManager.default
        try? paths.create()
        let size = (try? files.attributesOfItem(atPath: paths.events.path)[.size] as? Int) ?? 0
        if size > rotateAtBytes {
            try? files.removeItem(at: paths.rotatedEvents)
            try? files.moveItem(at: paths.events, to: paths.rotatedEvents)
        }
        if !files.fileExists(atPath: paths.events.path) {
            files.createFile(atPath: paths.events.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: paths.events)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
#endif
