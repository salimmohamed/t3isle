import Foundation

public struct T3Home: Sendable {
    public static let fallbackOrigin = URL(string: "http://127.0.0.1:3773")!
    private static let localHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    public let root: URL

    public init(root: URL = T3Home.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        if let custom = ProcessInfo.processInfo.environment["T3CODE_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3")
    }

    public var cachesDirectory: URL { root.appendingPathComponent("caches") }
    public var runtimeFile: URL { root.appendingPathComponent("userdata/server-runtime.json") }
    public var environmentIdFile: URL { root.appendingPathComponent("userdata/environment-id") }
    public var stateDatabase: URL { root.appendingPathComponent("userdata/statev2.sqlite") }
    public var cliTool: URL { root.appendingPathComponent("bin/t3") }

    public func serverOrigin() -> URL {
        guard let data = try? Data(contentsOf: runtimeFile),
              let origin = Self.origin(fromRuntime: data)
        else { return Self.fallbackOrigin }
        return origin
    }

    static func origin(fromRuntime data: Data) -> URL? {
        guard let runtime = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let origin = (runtime["origin"] as? String).flatMap(URL.init(string:)),
              localHosts.contains(origin.host ?? "")
        else { return nil }
        return origin
    }

    public func environmentId() -> String? {
        (try? String(contentsOf: environmentIdFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum WireDate {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: string) ?? plain.date(from: string)
    }

    static func format(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return fractional.string(from: date)
    }
}
