#if DEBUG
import Foundation

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

    public init(folders: StateFolders, rotateAtBytes: Int = 5_000_000) {
        queue.async { [self] in handle = Self.open(folders, rotateAtBytes: rotateAtBytes) }
    }

    public func record(_ name: String, _ attributes: [String: String] = [:], at time: Date = Date()) {
        let line = Data((DebugEvent(time: time, name: name, attributes: attributes).line + "\n").utf8)
        queue.async { [self] in try? handle?.write(contentsOf: line) }
    }

    public func flush() {
        queue.sync {}
    }

    private static func open(_ folders: StateFolders, rotateAtBytes: Int) -> FileHandle? {
        let files = FileManager.default
        try? folders.createLogs()
        let size = (try? files.attributesOfItem(atPath: folders.eventLog.path)[.size] as? Int) ?? 0
        if size > rotateAtBytes {
            try? files.removeItem(at: folders.rotatedEventLog)
            try? files.moveItem(at: folders.eventLog, to: folders.rotatedEventLog)
        }
        if !files.fileExists(atPath: folders.eventLog.path) {
            files.createFile(atPath: folders.eventLog.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: folders.eventLog)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
#endif
