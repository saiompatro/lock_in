import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Include the running session so the dashboard moves while you study.
        let now = model.now
        var records = model.sessions.sessions
        if let live = model.engine.liveRecord(at: now) { records.insert(live, at: 0) }
        let stats = DashboardStats(records: records, now: now)

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                PageHeader(
                    title: UIFormat.greeting(at: now),
                    subtitle: now.formatted(.dateTime.weekday(.wide).month(.wide).day())
                )

                if model.isSessionActive {
                    LiveSessionCard()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if stats.totalSessions == 0 && !model.isSessionActive {
                    firstRunCard
                }

                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    GoalCard(stats: stats)
                        .frame(width: 280)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                        GridItem(.flexible(), spacing: Theme.Spacing.m)],
                              spacing: Theme.Spacing.m) {
                        MetricCard(title: "Focus rate",
                                   value: stats.todayFocusRate.map(UIFormat.percent) ?? "—",
                                   caption: "of tracked time today",
                                   symbol: "scope", tint: Theme.studying)
                        MetricCard(title: "Distractions",
                                   value: "\(stats.todayDistractions)",
                                   caption: stats.todayDistractions == 0 ? "None so far today" : "today",
                                   symbol: "bolt.horizontal.fill", tint: Theme.distracted)
                        MetricCard(title: "Day streak",
                                   value: "\(stats.streakDays)",
                                   caption: stats.streakDays == 1 ? "day in a row" : "days in a row",
                                   symbol: "flame.fill", tint: .orange)
                        MetricCard(title: "Sessions",
                                   value: "\(stats.todaySessions)",
                                   caption: "today",
                                   symbol: "timer", tint: Theme.accent)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                WeekChartCard(stats: stats)

                InsightsSection(stats: stats)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .animation(Theme.smooth, value: model.isSessionActive)
    }

    private var firstRunCard: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(Theme.brandGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your focus story starts here")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.canStartSession
                     ? "Start a session and your stats will show up on this page."
                     : "Add a study space, then start a session to see your stats here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.canStartSession {
                Button("Start session") { model.startSession() }
                    .buttonStyle(.lockInPrimary(expands: false))
            } else {
                Button("Add study spaces") { model.selectedSection = .spaces }
                    .buttonStyle(.lockInPrimary(expands: false))
            }
        }
        .card(padding: Theme.Spacing.m)
    }
}

// MARK: - Live session

private struct LiveSessionCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            SessionHeroView()
                .frame(width: 240)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("Current session")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    LiveStatusPill()
                }
                SessionStatsRow()
                SessionControls(inMenuBar: false)
            }
        }
        .card()
    }
}

private struct LiveStatusPill: View {
    @Environment(AppModel.self) private var model
    var body: some View { StatusPill(status: model.status) }
}

// MARK: - Goal ring

private struct GoalCard: View {
    @Environment(AppModel.self) private var model
    let stats: DashboardStats

    var body: some View {
        let goal = max(60, model.settings.dailyGoalMinutes * 60)
        let progress = stats.todayFocused / goal
        let reached = progress >= 1
        VStack(spacing: Theme.Spacing.m) {
            HStack {
                Text("Today's goal")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if reached {
                    Label("Reached", systemImage: "checkmark.seal.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.studying)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            ProgressRing(progress: progress, lineWidth: 14, tint: reached ? Theme.studying : Theme.accent) {
                VStack(spacing: 2) {
                    Text(UIFormat.duration(stats.todayFocused))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Theme.snappy, value: stats.todayFocused)
                    Text("of \(UIFormat.duration(goal))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 156, height: 156)
            .padding(.vertical, 4)
            Text(caption(progress: progress, goal: goal))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .card()
        .animation(Theme.smooth, value: reached)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily goal: \(UIFormat.duration(stats.todayFocused)) of \(UIFormat.duration(goal))")
    }

    private func caption(progress: Double, goal: TimeInterval) -> String {
        if progress >= 1 { return "Goal smashed. Anything extra is a bonus." }
        if progress <= 0 { return "Focus for \(UIFormat.duration(goal)) to hit today's goal." }
        return "\(UIFormat.duration(goal - stats.todayFocused)) to go. You've got this."
    }
}

// MARK: - Week chart

private struct WeekChartCard: View {
    let stats: DashboardStats

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String
        let minutes: Double
    }

    private var points: [Point] {
        stats.week.flatMap { day in
            [Point(date: day.date, kind: "Focused", minutes: day.focusedMinutes),
             Point(date: day.date, kind: "Distracted", minutes: day.distractedMinutes)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last 7 days")
                        .font(.system(size: 13, weight: .semibold))
                    Text(stats.weekHasData
                         ? "\(UIFormat.duration(stats.week.reduce(0) { $0 + $1.focusedMinutes } * 60)) focused this week"
                         : "Your week at a glance")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Theme.Spacing.s) {
                    legend("Focused", Theme.studying)
                    legend("Distracted", Theme.distracted)
                }
            }

            ZStack {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Minutes", point.minutes),
                        width: .ratio(0.5)
                    )
                    .foregroundStyle(by: .value("Type", point.kind))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(["Focused": Theme.studying, "Distracted": Theme.distracted])
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(minutes == 0 ? "0" : UIFormat.duration(minutes * 60))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 190)
                .opacity(stats.weekHasData ? 1 : 0.35)

                if !stats.weekHasData {
                    Text("Complete a session to see your week.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Insights

private struct InsightsSection: View {
    let stats: DashboardStats

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Insights")
                .font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                InsightCard(
                    symbol: "sun.max.fill", tint: .orange,
                    title: "Best focus hour",
                    value: stats.bestHour.map { UIFormat.hourLabel($0) } ?? "—",
                    caption: stats.bestHour.map { "You focus most around \(UIFormat.hourLabel($0)). Past 30 days." }
                        ?? "Not enough data yet."
                )
                InsightCard(
                    symbol: "eye.slash.fill", tint: Theme.distracted,
                    title: "Top distractor",
                    value: stats.topDistractor?.name ?? "—",
                    caption: stats.topDistractor.map { "\(UIFormat.duration($0.seconds)) lost to it. Past 30 days." }
                        ?? "No distractions recorded. Nice."
                )
                InsightCard(
                    symbol: "hourglass", tint: Theme.accent,
                    title: "Time before distraction",
                    value: stats.averageBeforeDistraction.map(UIFormat.duration) ?? "—",
                    caption: stats.averageBeforeDistraction != nil
                        ? "Average focus between distractions." : "Not enough data yet."
                )
                InsightCard(
                    symbol: "trophy.fill", tint: Theme.violet,
                    title: "Longest focus streak",
                    value: stats.longestStreak.map(UIFormat.duration) ?? "—",
                    caption: stats.longestStreak != nil ? "Uninterrupted, this week." : "Not enough data yet."
                )
            }
        }
    }
}

private struct InsightCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let caption: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.13)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }
}
