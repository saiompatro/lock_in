import Foundation

struct DayStat: Identifiable, Hashable {
    var date: Date
    var focusedMinutes: Double
    var distractedMinutes: Double
    var id: Date { date }
}

/// Pure aggregation of session records into the numbers shown on the dashboard.
struct DashboardStats {
    var todayFocused: TimeInterval = 0
    var todayDistracted: TimeInterval = 0
    var todayDistractions = 0
    var todaySessions = 0
    var streakDays = 0
    /// Last 7 days, oldest first, ending today.
    var week: [DayStat] = []
    var bestHour: Int?
    var topDistractor: (name: String, seconds: TimeInterval)?
    var averageBeforeDistraction: TimeInterval?
    var longestStreak: TimeInterval?
    var totalSessions = 0

    var todayFocusRate: Double? {
        let total = todayFocused + todayDistracted
        return total > 0 ? todayFocused / total : nil
    }

    var weekHasData: Bool { week.contains { $0.focusedMinutes + $0.distractedMinutes > 0 } }

    /// Window (in days) used for the "insight" cards.
    static let insightDays = 30

    init() {}

    init(records: [StudySessionRecord], now: Date, calendar cal: Calendar = .current) {
        totalSessions = records.count
        let today = cal.startOfDay(for: now)

        // Today
        for r in records where cal.isDate(r.startedAt, inSameDayAs: now) {
            todayFocused += r.focusedSeconds
            todayDistracted += r.distractedSeconds
            todayDistractions += r.distractionCount
            todaySessions += 1
        }

        // Streak: consecutive days with at least one session, ending today (or yesterday if today is empty).
        let days = Set(records.map { cal.startOfDay(for: $0.startedAt) })
        var cursor = days.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        streakDays = streak

        // Last 7 days
        var buckets: [Date: (Double, Double)] = [:]
        for r in records {
            let day = cal.startOfDay(for: r.startedAt)
            var b = buckets[day] ?? (0, 0)
            b.0 += r.focusedSeconds / 60
            b.1 += r.distractedSeconds / 60
            buckets[day] = b
        }
        week = (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let b = buckets[day] ?? (0, 0)
            return DayStat(date: day, focusedMinutes: b.0, distractedMinutes: b.1)
        }

        // Insights
        let insightStart = cal.date(byAdding: .day, value: -(Self.insightDays - 1), to: today) ?? today
        let recent = records.filter { $0.startedAt >= insightStart }
        bestHour = Self.bestFocusHour(recent, calendar: cal)

        var byApp: [String: TimeInterval] = [:]
        for r in recent {
            for e in r.distractions {
                guard let name = e.appName, !name.isEmpty else { continue }
                byApp[name, default: 0] += e.duration
            }
        }
        if let top = byApp.max(by: { $0.value < $1.value }) {
            topDistractor = (top.key, top.value)
        }

        let withDistractions = recent.filter { $0.distractionCount > 0 }
        let distractionTotal = withDistractions.reduce(0) { $0 + $1.distractionCount }
        if distractionTotal > 0 {
            averageBeforeDistraction = withDistractions.reduce(0) { $0 + $1.focusedSeconds } / Double(distractionTotal)
        }

        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today
        longestStreak = records.filter { $0.startedAt >= weekStart }.map(\.longestFocusStreak).max().flatMap { $0 > 0 ? $0 : nil }
    }

    /// Hour of day with the most focused time, spreading each session across the hours it covered
    /// (minus the distraction episodes inside it).
    private static func bestFocusHour(_ records: [StudySessionRecord], calendar cal: Calendar) -> Int? {
        var hours = [Double](repeating: 0, count: 24)
        for r in records where r.endedAt > r.startedAt && r.focusedSeconds > 0 {
            var raw = [Double](repeating: 0, count: 24)
            accumulate(&raw, from: r.startedAt, to: r.endedAt, sign: 1, calendar: cal)
            for e in r.distractions {
                accumulate(&raw, from: e.start, to: e.start.addingTimeInterval(e.duration), sign: -1, calendar: cal)
            }
            let positive = raw.map { max(0, $0) }
            let sum = positive.reduce(0, +)
            guard sum > 0 else { continue }
            let scale = r.focusedSeconds / sum
            for h in 0..<24 { hours[h] += positive[h] * scale }
        }
        guard let best = hours.enumerated().max(by: { $0.element < $1.element }), best.element > 0 else { return nil }
        return best.offset
    }

    private static func accumulate(_ buckets: inout [Double], from start: Date, to end: Date, sign: Double, calendar cal: Calendar) {
        var cursor = start
        var guardCount = 0
        while cursor < end, guardCount < 24 * 14 {
            guard let interval = cal.dateInterval(of: .hour, for: cursor) else { break }
            let segmentEnd = min(interval.end, end)
            let hour = cal.component(.hour, from: cursor)
            buckets[hour] += sign * segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
            guardCount += 1
        }
    }
}
