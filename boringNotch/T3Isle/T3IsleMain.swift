import Foundation
import OSLog
import T3IsleCore

@main
enum T3IsleMain {
    @MainActor
    static func main() {
        #if DEBUG
        do {
            try StateFolders.current.isolate()
        } catch {
            Logger(subsystem: bundleIdentifier, category: "state-dir")
                .fault("cannot use \(StateFolders.flag, privacy: .public): \(String(describing: error), privacy: .public)")
            exit(EXIT_FAILURE)
        }
        #endif
        DynamicNotchApp.main()
    }
}
