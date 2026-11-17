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

    public var eventLog: URL { logs.appendingPathComponent("events.ndjson") }
    public var stateFile: URL { logs.appendingPathComponent("state.json") }

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
        if let root = root(in: arguments, currentDirectory: currentDirectory) { return isolated(in: root) }
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
        case folderNotCreated(String)
        case defaultsNotRedirected(String)
    }

    public static let flag = "--state-dir"

    public var defaults: URL? { root?.appendingPathComponent("defaults.plist") }
    public var launchArguments: [String] { root.map { [Self.flag, $0.path] } ?? [] }

    public static func isolated(in root: URL) -> StateFolders {
        StateFolders(
            root: root,
            session: root.appendingPathComponent("session.json"),
            shelf: root.appendingPathComponent("Shelf", isDirectory: true),
            logs: root.appendingPathComponent("logs", isDirectory: true)
        )
    }

    static func root(in arguments: [String], currentDirectory: URL) -> URL? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        let path = arguments[index + 1]
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true, relativeTo: currentDirectory).absoluteURL.standardizedFileURL
    }

    public func isolate() throws {
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
