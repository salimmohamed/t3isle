import Foundation

public enum Format {
    public static func clock(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400, hours = total % 86_400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "now"
    }

    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func ago(_ date: Date?, now: Date) -> String {
        date.map { duration(now.timeIntervalSince($0)) } ?? ""
    }
}

public enum SnoozeOption {
    public static func choices(from now: Date, calendar: Calendar = .current) -> [(title: String, date: Date)] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now).flatMap {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
        } ?? now.addingTimeInterval(86400)
        var monday = DateComponents(hour: 9, minute: 0)
        monday.weekday = 2
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let nextWeek = calendar.nextDate(after: startOfTomorrow, matching: monday, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(7 * 86400)
        return [
            ("1h", now.addingTimeInterval(3600)), ("3h", now.addingTimeInterval(3 * 3600)),
            ("Tomorrow", tomorrow), ("Next week", nextWeek),
        ]
    }
}
