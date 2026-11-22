import Foundation

public enum NotchTab: String, CaseIterable, Codable, Sendable {
    case home, t3, shelf

    public static func barShown(t3Enabled: Bool, shelfEnabled: Bool, shelfEmpty: Bool, alwaysShowTabs: Bool) -> Bool {
        t3Enabled || shelfEnabled && (alwaysShowTabs || !shelfEmpty)
    }

    public static func resolvedOnDisplay(notchOpen: Bool, anyNotchOpen: Bool) -> Bool {
        notchOpen || !anyNotchOpen
    }

    public func whileOpen(barShown: Bool, t3Enabled: Bool) -> NotchTab {
        barShown && (self != .t3 || t3Enabled) ? self : .home
    }
}

public enum OpeningTab: String, CaseIterable, Sendable {
    case home, t3, shelf, last

    public var title: String {
        switch self {
        case .home: "Home"
        case .t3: "T3"
        case .shelf: "Shelf"
        case .last: "Last used tab"
        }
    }

    public func tab(current: NotchTab, t3Ready: Bool, shelfFirst: Bool, barShown: Bool) -> NotchTab {
        guard barShown else { return .home }
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
