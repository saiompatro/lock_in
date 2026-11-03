import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var confirmClear = false

    private var sessions: [StudySessionRecord] { model.sessions.sessions }

    private var days: [(day: Date, sessions: [StudySessionRecord])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "History", subtitle: subtitle) {
                if !sessions.isEmpty {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.lockInSoft(tint: Theme.distracted))
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.m)

            if sessions.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "No sessions yet",
                        message: "Finished sessions show up here with a breakdown of your focus and distractions.",
                        actionTitle: model.isSessionActive ? nil : (model.canStartSession ? "Start a Session" : nil),
                        action: { model.startSession() }
                    )
                    .padding(.top, Theme.Spacing.xl)
                }
            } else {
                HStack(spacing: 0) {
                    sessionList
                        .frame(width: 330)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .confirmationDialog("Delete all session history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All Sessions", role: .destructive) {
                withAnimation(Theme.smooth) {
                    model.sessions.deleteAll()
                    selection = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(UIFormat.count(sessions.count, "session")). It can't be undone.")
        }
        .onAppear { if selection == nil { selection = sessions.first?.id } }
    }

    private var subtitle: String {
        guard !sessions.isEmpty else { return "Every session you finish is saved here" }
        let total = sessions.reduce(0) { $0 + $1.focusedSeconds }
        return "\(UIFormat.count(sessions.count, "session")) · \(UIFormat.duration(total)) focused in total"
    }

    // MARK: List

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.sessions) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                Button("Delete Session", systemImage: "trash", role: .destructive) { delete(session) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { delete(session) }
                            }
                    }
                } header: {
                    HStack {
                        Text(UIFormat.dayTitle(group.day))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(UIFormat.duration(group.sessions.reduce(0) { $0 + $1.focusedSeconds }))
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var detail: some View {
        if let session = sessions.first(where: { $0.id == selection }) {
            SessionDetailView(session: session) { delete(session) }
                .id(session.id)
                .transition(.opacity)
        } else {
            EmptyStateView(symbol: "hand.point.left.fill", title: "Select a session",
                           message: "Pick a session on the left to see how it went.")
        }
    }

    private func delete(_ session: StudySessionRecord) {
        let ids = sessions.map(\.id)
        let index = ids.firstIndex(of: session.id)
        withAnimation(Theme.smooth) {
            model.sessions.delete(id: session.id)
            if selection == session.id {
                let remaining = model.sessions.sessions.map(\.id)
                if let index, !remaining.isEmpty {
                    selection = remaining[min(index, remaining.count - 1)]
                } else {
                    selection = nil
                }
            }
        }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: StudySessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(UIFormat.timeRange(session.startedAt, session.endedAt))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(UIFormat.duration(session.totalTrackedSeconds))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            FocusBar(focused: session.focusedSeconds, distracted: session.distractedSeconds, height: 5)
            HStack(spacing: 10) {
                Text("\(UIFormat.percent(session.focusRate)) focused")
                Text("·")
                Text(UIFormat.count(session.distractionCount, "distraction"))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct SessionDetailView: View {
    let session: StudySessionRecord
    let onDelete: () -> Void
    @State private var confirmDelete = false

    private var duration: TimeInterval { session.endedAt.timeIntervalSince(session.startedAt) }

    private var breakdown: [(name: String, seconds: TimeInterval)] {
        session.spaceBreakdown.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("\(UIFormat.timeRange(session.startedAt, session.endedAt)) · \(UIFormat.duration(duration))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.lockInIcon(tint: Theme.distracted))
                    .help("Delete session")
                    .accessibilityLabel("Delete session")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.m) {
                        stat("Focused", UIFormat.duration(session.focusedSeconds), Theme.studying)
                        stat("Distracted", UIFormat.duration(session.distractedSeconds), Theme.distracted)
                        stat("Focus rate", UIFormat.percent(session.focusRate), .primary)
                        stat("Alerts", "\(session.alertCount)", .primary)
                    }
                    FocusBar(focused: session.focusedSeconds, distracted: session.distractedSeconds,
                             paused: session.pausedSeconds, height: 10)
                    HStack(spacing: Theme.Spacing.m) {
                        legend("Focused", Theme.studying)
                        legend("Distracted", Theme.distracted)
                        if session.pausedSeconds > 1 {
                            legend("Paused \(UIFormat.duration(session.pausedSeconds))", Theme.paused)
                        }
                        Spacer()
                        if session.longestFocusStreak > 0 {
                            Label("Best streak \(UIFormat.duration(session.longestFocusStreak))", systemImage: "flame.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .card()

                distractionsCard

                if !breakdown.isEmpty { spacesCard }
            }
            .padding(Theme.Spacing.l)
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from your history and stats.")
        }
    }

    private func stat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    // MARK: Distractions

    private var distractionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Distractions")
                .font(.system(size: 13, weight: .semibold))
            if session.distractions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.studying)
                    Text("No distractions. A perfectly focused session.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    let events = session.distractions.sorted { $0.start < $1.start }
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .top, spacing: Theme.Spacing.s) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(event.triggeredAlert ? Theme.distracted : Theme.distracted.opacity(0.45))
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 5)
                                if index < events.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1.5)
                                }
                            }
                            .frame(width: 10)
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.appName ?? "Another app")
                                        .font(.system(size: 13, weight: .medium))
                                    Text(UIFormat.time(event.start))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if event.triggeredAlert {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.distracted)
                                        .help("Alert was sent")
                                }
                                Text(UIFormat.duration(event.duration))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .padding(.bottom, Theme.Spacing.s)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Spaces

    private var spacesCard: some View {
        let maxValue = max(breakdown.map(\.seconds).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Where you focused")
                .font(.system(size: 13, weight: .semibold))
            ForEach(breakdown, id: \.name) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text(UIFormat.duration(item.seconds))
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        Capsule().fill(Theme.studying.gradient)
                            .frame(width: max(6, geo.size.width * item.seconds / maxValue))
                    }
                    .frame(height: 6)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
