import AppKit
import SwiftUI

/// Closes the MenuBarExtra panel (so opening the main window doesn't leave it hanging open).
@MainActor
enum MenuBarPanel {
    static func dismiss() {
        let panels = NSApp.windows.filter { String(describing: type(of: $0)).contains("MenuBarExtra") }
        if panels.isEmpty {
            if let key = NSApp.keyWindow, key is NSPanel, key.level.rawValue > NSWindow.Level.normal.rawValue {
                key.close()
            }
        } else {
            panels.forEach { $0.close() }
        }
    }
}

// MARK: - Big timer

struct BigTimer: View {
    let seconds: TimeInterval
    var size: CGFloat = 46
    var color: Color = .primary

    var body: some View {
        let text = DurationFormat.clock(seconds)
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(Theme.snappy, value: text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Hero

/// The big, central readout of the current session state. Used in the menu bar panel and on the dashboard.
struct SessionHeroView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.now
        ZStack {
            switch model.status {
            case .idle:
                IdleHero()
                    .transition(heroTransition)
            case .studying:
                StudyingHero(now: now)
                    .transition(heroTransition)
            case .distracted:
                DistractedHero(now: now)
                    .transition(heroTransition)
            case .paused:
                PausedHero(now: now)
                    .transition(heroTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.smooth, value: model.status)
    }

    private var heroTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)),
            removal: .opacity.combined(with: .scale(scale: 1.04))
        )
    }
}

private struct IdleHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let today = DashboardStats(records: model.sessions.sessions, now: Date())
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: "lock.open")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.brandGradient)
            }
            Text("Ready to focus")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(today.todayFocused > 0
                 ? "\(UIFormat.duration(today.todayFocused)) focused today"
                 : "Start a session and Lock In keeps you honest.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 4)
    }
}

private struct StudyingHero: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let engine = model.engine
        VStack(spacing: 8) {
            Text("FOCUSED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.studying)
            BigTimer(seconds: engine.focusedTime(at: now), size: 52)
            if let space = engine.currentSpace {
                HStack(spacing: 6) {
                    SpaceIconView(space: space, size: 18)
                    Text(space.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.leading, 5)
                .padding(.trailing, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.studying.opacity(0.13)))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .id(space.id)
                .accessibilityLabel("Studying in \(space.name)")
            }
        }
        .animation(Theme.smooth, value: engine.currentSpace?.id)
    }
}

private struct DistractedHero: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let engine = model.engine
        let elapsed = engine.currentDistractionElapsed(at: now)
        let threshold = model.settings.distractionThreshold
        let remaining = max(0, threshold - elapsed)
        let past = elapsed >= threshold
        VStack(spacing: 12) {
            ProgressRing(progress: min(1, elapsed / threshold), lineWidth: 10, tint: Theme.distracted) {
                VStack(spacing: 2) {
                    BigTimer(seconds: elapsed, size: 32, color: Theme.distracted)
                    Text("away")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, height: 128)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Distracted for \(DurationFormat.clock(elapsed))")

            VStack(spacing: 3) {
                Text(past ? "Alert sent" : "Alert in \(DurationFormat.clock(remaining))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.snappy, value: remaining)
                if let name = engine.lastSnapshot?.appName {
                    Text("Currently in \(name)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct PausedHero: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let engine = model.engine
        VStack(spacing: 10) {
            switch engine.pauseReason {
            case .onBreak:
                let remaining = engine.breakRemaining(at: now) ?? 0
                let total = max(60, model.settings.breakMinutes * 60)
                ProgressRing(progress: 1 - min(1, remaining / total), lineWidth: 8, tint: Theme.accent) {
                    VStack(spacing: 2) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                        BigTimer(seconds: remaining, size: 28)
                    }
                }
                .frame(width: 118, height: 118)
                Text("On a break")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Back to it when the timer ends.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .away:
                pausedBody(symbol: "moon.zzz.fill", title: "Paused while you're away",
                           caption: "Tracking resumes when your Mac wakes up.", now: now)
            default:
                pausedBody(symbol: "pause.circle.fill", title: "Session paused",
                           caption: "Nothing is being tracked right now.", now: now)
            }
        }
    }

    @ViewBuilder
    private func pausedBody(symbol: String, title: String, caption: String, now: Date) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 34))
            .foregroundStyle(Theme.paused)
            .symbolRenderingMode(.hierarchical)
        BigTimer(seconds: model.engine.focusedTime(at: now), size: 40, color: .secondary)
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        Text(caption)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Stats row

/// Compact three-up stats: live for the running session, "today" when idle.
struct SessionStatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.now
        HStack(spacing: 0) {
            if model.isSessionActive {
                let engine = model.engine
                StatTile(title: "Focused", value: UIFormat.duration(engine.focusedTime(at: now)), tint: Theme.studying)
                divider
                StatTile(title: "Distracted", value: UIFormat.duration(engine.distractedTime(at: now)), tint: Theme.distracted)
                divider
                StatTile(title: "Distractions", value: "\(engine.distractionCount)")
            } else {
                let stats = DashboardStats(records: model.sessions.sessions, now: Date())
                StatTile(title: "Focused today", value: UIFormat.duration(stats.todayFocused), tint: Theme.studying)
                divider
                StatTile(title: "Sessions", value: "\(stats.todaySessions)")
                divider
                StatTile(title: "Day streak", value: "\(stats.streakDays)")
            }
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.subtleFill))
        .animation(Theme.smooth, value: model.isSessionActive)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 26)
    }
}

// MARK: - Controls

/// Start / pause / break / stop. `inMenuBar` closes the panel before opening the main window.
struct SessionControls: View {
    @Environment(AppModel.self) private var model
    var inMenuBar = true

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if model.isSessionActive {
                activeControls
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                idleControls
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Theme.smooth, value: model.isSessionActive)
        .animation(Theme.smooth, value: model.canStartSession)
    }

    private var idleControls: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                model.startSession()
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(.lockInPrimary)
            .disabled(!model.canStartSession)
            .keyboardShortcut(.defaultAction)

            if !model.canStartSession {
                Text("Add a study space first, so Lock In knows what counts as studying.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add study spaces") { openMain(.spaces) }
                    .buttonStyle(.lockInSoft(tint: Theme.accent, expands: true))
            }
        }
    }

    private var activeControls: some View {
        let paused = model.status == .paused
        let onBreak: Bool = {
            if case .onBreak = model.engine.pauseReason { return true }
            return false
        }()
        return HStack(spacing: Theme.Spacing.xs) {
            Button {
                model.togglePause()
            } label: {
                Label(paused ? (onBreak ? "End break" : "Resume") : "Pause",
                      systemImage: paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lockInPrimary(tint: paused ? Theme.studying : Theme.accent))

            if !onBreak {
                Button {
                    model.takeBreak()
                } label: {
                    Label("Break", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.lockInSoft(expands: true))
                .frame(minHeight: 36)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .help("Pause tracking for \(Int(model.settings.breakMinutes)) minutes")
            }

            Button {
                model.stopSession()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.lockInSoft(tint: Theme.distracted, expands: true))
            .frame(minHeight: 36)
        }
        .animation(Theme.smooth, value: onBreak)
        .animation(Theme.smooth, value: paused)
    }

    private func openMain(_ section: MainSection) {
        if inMenuBar { MenuBarPanel.dismiss() }
        model.openMainWindow(section)
    }
}
