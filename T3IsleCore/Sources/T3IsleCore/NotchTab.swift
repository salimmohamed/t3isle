import Foundation

public enum NotchTab: String, CaseIterable, Sendable {
    case home, t3, shelf
}

public enum OpeningTab: String, CaseIterable, Sendable {
    case home, t3, shelf, last

    public static func migrated(rememberLastTab: Bool) -> OpeningTab {
        rememberLastTab ? .last : .t3
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .t3: "T3"
        case .shelf: "Shelf"
        case .last: "Last used tab"
        }
    }

    public func tab(current: NotchTab, t3Ready: Bool, shelfFirst: Bool) -> NotchTab {
        if shelfFirst { return .shelf }
        let wanted: NotchTab = switch self {
        case .home: .home
        case .t3: .t3
        case .shelf: .shelf
        case .last: current
        }
        return wanted == .t3 && !t3Ready ? .home : wanted
    }
}
