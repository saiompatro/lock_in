import Foundation

/// Display formatting shared across the UI. (Clock-style formatting lives in `DurationFormat`.)
enum UIFormat {
    /// "2h 15m", "45m", "30s", "0m".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s == 0 { return "0m" }
        return DurationFormat.short(TimeInterval(s))
    }

    /// "42%".
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// "2:14 PM".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "2:14 PM – 3:02 PM".
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "Today", "Yesterday", or "Monday, Oct 26".
    static func dayTitle(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "3 PM".
    static func hourLabel(_ hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    static func greeting(at date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Burning the midnight oil?"
        }
    }

    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
