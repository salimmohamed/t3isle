import Foundation
#if DEBUG
import ObjectiveC
#endif

public struct StateFolders: Equatable, Sendable {
    public static let installedAppName = "T3 Isle"
    static let inheritedShelfOwner = "boringNotch"

    public let root: URL?
    public let session: URL
    public let shelf: URL
    public let logs: URL
    public var missingPath = false

    public static let current = resolve(
        arguments: CommandLine.arguments,
        currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        appName: appName(),
        library: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    )

    public static func appName(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? installedAppName
    }

    public static func resolve(arguments: [String], currentDirectory: URL, appName: String, library: URL) -> StateFolders {
        #if DEBUG
        switch request(in: arguments, currentDirectory: currentDirectory) {
        case .isolated(let root): return isolated(in: root)
        case .missingPath:
            var folders = standard(appName: appName, library: library)
            folders.missingPath = true
            return folders
        case .standard: break
        }
        #endif
        return standard(appName: appName, library: library)
    }

    public static func standard(appName: String, library: URL) -> StateFolders {
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        let own = support.appendingPathComponent(appName, isDirectory: true)
        let shelfOwner = appName == installedAppName
            ? support.appendingPathComponent(inheritedShelfOwner, isDirectory: true)
            : own
        return StateFolders(
            root: nil,
            session: own.appendingPathComponent("session.json"),
            shelf: shelfOwner.appendingPathComponent("Shelf", isDirectory: true),
            logs: library.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent(appName, isDirectory: true)
        )
    }
}

#if DEBUG
extension StateFolders {
    public enum Failure: Error, Equatable {
        case missingPath
        case folderNotCreated(String)
        case defaultsNotRedirected(String)
    }

    public static let flag = "--state-dir"

    public var defaults: URL? { root?.appendingPathComponent("defaults.plist") }
    public var eventLog: URL { logs.appendingPathComponent("events.ndjson") }
    public var rotatedEventLog: URL { logs.appendingPathComponent("events.1.ndjson") }
    public var stateFile: URL { logs.appendingPathComponent("state.json") }
    public var launchArguments: [String] { root.map { [Self.flag, $0.path] } ?? [] }

    public static func isolated(in root: URL) -> StateFolders {
        StateFolders(
            root: root,
            session: root.appendingPathComponent("session.json"),
            shelf: root.appendingPathComponent("Shelf", isDirectory: true),
            logs: root.appendingPathComponent("logs", isDirectory: true)
        )
    }

    enum Request: Equatable {
        case standard
        case isolated(URL)
        case missingPath
    }

    static func request(in arguments: [String], currentDirectory: URL) -> Request {
        guard let index = arguments.firstIndex(of: flag) else { return .standard }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].isEmpty else { return .missingPath }
        return .isolated(URL(fileURLWithPath: arguments[index + 1], isDirectory: true, relativeTo: currentDirectory)
            .absoluteURL.standardized)
    }

    public func createLogs() throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    }

    public func isolate() throws {
        guard !missingPath else { throw Failure.missingPath }
        guard let root, let defaults else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw Failure.folderNotCreated(root.path)
        }
        guard let suite = UserDefaults(suiteName: defaults.deletingPathExtension().path),
              let standard = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))
        else { throw Failure.defaultsNotRedirected(defaults.path) }
        let isolatedStandard: @convention(block) (AnyObject) -> UserDefaults = { _ in suite }
        method_setImplementation(standard, imp_implementationWithBlock(isolatedStandard))
    }
}
#endif
