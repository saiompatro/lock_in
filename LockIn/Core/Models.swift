import Foundation

// MARK: - Study spaces

/// What a study space matches against.
enum StudySpaceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Any focused, non-minimized window of an application.
    case app
    /// A specific window of an application, matched by a substring of its title.
    case window
    /// A website open in the active tab of a supported browser.
    case website

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: "App"
        case .window: "Window"
        case .website: "Website"
        }
    }

    var symbolName: String {
        switch self {
        case .app: "app.dashed"
        case .window: "macwindow"
        case .website: "globe"
        }
    }
}

/// A user-designated place where studying happens.
struct StudySpace: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: StudySpaceKind
    /// Display name, e.g. "Xcode", "Lecture 4.pdf", "docs.google.com".
    var name: String
    /// `.app` / `.window`: the owning app (required).
    /// `.website`: nil means "in any supported browser"; set to restrict to one browser.
    var bundleID: String?
    /// Human readable app name (for display only).
    var appName: String?
    /// `.window`: case-insensitive substring the focused window title must contain.
    /// `.website`: optional fallback keyword matched against the browser window title
    /// when the tab URL cannot be read (e.g. Firefox, or Automation permission denied).
    var titleContains: String?
    /// `.website`: "notion.so" (domain + all subdomains) or "docs.google.com/document/d/abc"
    /// (domain + path prefix). Scheme and leading "www." are ignored.
    var urlPattern: String?
    var isEnabled: Bool = true
    var createdAt: Date = Date()
}

// MARK: - Live activity

/// What the user is looking at right now. Produced by `ActivityMonitor`.
struct ActivitySnapshot: Equatable, Sendable {
    var timestamp: Date = Date()
    var bundleID: String?
    var appName: String?
    /// Title of the focused window. nil when unknown (Accessibility not granted, or no window).
    var windowTitle: String?
    /// True when Accessibility is granted, so `hasVisibleWindow` / `windowTitle` are trustworthy.
    var windowInfoAvailable: Bool = false
    /// False when the frontmost app has no focused, non-minimized window
    /// (all windows minimized, app hidden, or only the desktop is focused).
    /// Only meaningful when `windowInfoAvailable` is true.
    var hasVisibleWindow: Bool = true
    /// True when the frontmost app is a browser Lock In knows about.
    var isBrowser: Bool = false
    /// URL of the active tab. nil when not a browser, unreadable, or permission denied.
    var browserURL: URL?
    /// True when Lock In itself is frontmost (menu bar panel, settings, overlay).
    /// The engine treats this as neutral and keeps its current state.
    var isOwnApp: Bool = false

    /// Equality that ignores the timestamp, used to de-duplicate snapshots.
    func sameActivity(as other: ActivitySnapshot) -> Bool {
        var a = self, b = other
        a.timestamp = .distantPast
        b.timestamp = .distantPast
        return a == b
    }

    /// Short human-readable description, e.g. "Safari — notion.so" or "Preview — Lecture 4.pdf".
    var shortDescription: String {
        let app = appName ?? "Unknown app"
        if let host = browserURL?.host(percentEncoded: false) {
            return "\(app) — \(host.replacingOccurrences(of: "www.", with: ""))"
        }
        if let title = windowTitle, !title.isEmpty, title != app {
            return "\(app) — \(title)"
        }
        return app
    }
}

// MARK: - Sessions

enum SessionStatus: String, Codable, Sendable {
    /// No session running.
    case idle
    /// Session running and the user is in a study space.
    case studying
    /// Session running and the user is outside every study space.
    case distracted
    /// Session running but paused (manually, on a break, or while the Mac is locked/asleep).
    case paused

    var displayName: String {
        switch self {
        case .idle: "Not studying"
        case .studying: "Studying"
        case .distracted: "Distracted"
        case .paused: "Paused"
        }
    }
}

/// One stretch of time spent outside the study spaces.
struct DistractionEvent: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var start: Date
    var duration: TimeInterval
    /// Name of the app the user switched to (no URLs or titles are stored).
    var appName: String?
    /// Whether this episode crossed the alert threshold.
    var triggeredAlert: Bool = false
}

/// A finished study session, persisted to disk.
struct StudySessionRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var focusedSeconds: TimeInterval
    var distractedSeconds: TimeInterval
    var pausedSeconds: TimeInterval
    /// Episodes outside study spaces lasting at least `SessionEngine.minimumDistractionDuration`.
    var distractionCount: Int
    var alertCount: Int
    var longestFocusStreak: TimeInterval
    var distractions: [DistractionEvent]
    /// Focused seconds per study space name.
    var spaceBreakdown: [String: TimeInterval]

    var totalTrackedSeconds: TimeInterval { focusedSeconds + distractedSeconds }

    /// 0...1 share of tracked (non-paused) time spent focused.
    var focusRate: Double {
        let total = totalTrackedSeconds
        return total > 0 ? focusedSeconds / total : 0
    }
}

/// Passed to the alert layer when the threshold is crossed.
struct AlertContext: Sendable, Equatable {
    var distractedFor: TimeInterval
    var distractingAppName: String?
    /// Last study space the user was in, so "Back to studying" can jump there.
    var lastStudySpace: StudySpace?
    /// True for follow-up reminders within the same distraction episode.
    var isRepeat: Bool
}

// MARK: - Formatting helpers

enum DurationFormat {
    /// "1:05:09" or "5:09".
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "2h 15m", "45m", "30s".
    static func short(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
