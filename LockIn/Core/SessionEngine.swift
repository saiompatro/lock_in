import Foundation
import Observation

// Foundation + Observation only (no AppKit): this file is compiled into the unit-test target.

/// The session state machine. All time math is timestamp-based (never tick counting),
/// so readouts stay accurate even if timers are delayed or coalesced in the background.
@MainActor
@Observable
final class SessionEngine {
    enum PauseReason: Equatable, Sendable {
        case manual
        case onBreak(until: Date)
        case away
    }

    /// Distraction episodes shorter than this are not counted as "distractions"
    /// (their time still counts as distracted time).
    static let minimumDistractionDuration: TimeInterval = 15

    /// If an alert is handled more than this long after its deadline (clock jump, sleep without
    /// away events, throttled timers) the repeat schedule restarts from "now" instead of the grid.
    private static let lateAlertTolerance: TimeInterval = 5

    private(set) var status: SessionStatus = .idle
    private(set) var pauseReason: PauseReason?
    private(set) var sessionID: UUID?
    private(set) var sessionStartedAt: Date?
    /// Study space the user is in right now (nil unless studying).
    private(set) var currentSpace: StudySpace?
    /// Most recent study space the user was in during this session.
    private(set) var lastStudySpace: StudySpace?
    /// Last non-own-app snapshot ingested.
    private(set) var lastSnapshot: ActivitySnapshot?
    /// Start of the current distraction episode (nil unless distracted).
    private(set) var distractionStartedAt: Date?
    /// Distraction episodes that have ended and were long enough to count (see `countsAsDistraction`).
    private(set) var distractionCount: Int = 0
    private(set) var alertCount: Int = 0

    /// Seconds outside study spaces before `onAlert` fires.
    var distractionThreshold: TimeInterval = 300 {
        didSet { if distractionThreshold != oldValue { rescheduleTimers() } }
    }
    /// Seconds between follow-up alerts in one episode; nil = alert once per episode.
    var repeatInterval: TimeInterval? = 300 {
        didSet { if repeatInterval != oldValue { rescheduleTimers() } }
    }

    /// Fired when an episode crosses the threshold (and on each repeat).
    var onAlert: ((AlertContext) -> Void)?
    /// Fired when a distraction episode ends (user returned, paused, or stopped).
    var onDistractionEnded: (() -> Void)?
    /// Fired by `stop()` with the finished record.
    var onSessionEnded: ((StudySessionRecord) -> Void)?
    /// Fired when a break ends and the session auto-resumes.
    var onBreakEnded: (() -> Void)?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let schedulesTimers: Bool

    // MARK: Internal accounting (all timestamp based)

    /// Closed time per status.
    @ObservationIgnored private var focusedAcc: TimeInterval = 0
    @ObservationIgnored private var distractedAcc: TimeInterval = 0
    @ObservationIgnored private var pausedAcc: TimeInterval = 0
    /// Focused seconds per space name for closed studying segments.
    @ObservationIgnored private var spaceAcc: [String: TimeInterval] = [:]
    /// Start of the open segment of the current status (and, while studying, of the current space).
    @ObservationIgnored private var segmentStart: Date?
    /// Start of the current uninterrupted studying stretch (survives space switches).
    @ObservationIgnored private var streakStart: Date?
    @ObservationIgnored private var closedLongestStreak: TimeInterval = 0
    /// Ended episodes that count as distractions.
    @ObservationIgnored private var events: [DistractionEvent] = []
    /// Per-episode state.
    @ObservationIgnored private var episodeAppName: String?
    @ObservationIgnored private var alertsInEpisode = 0
    @ObservationIgnored private var alertAnchor: Date?
    /// The space of the last ingested (non-own-app) snapshot; decides the state on resume.
    @ObservationIgnored private var lastMatched: StudySpace?
    /// The Mac went away while a break was running; when the break expires it becomes `.away`.
    @ObservationIgnored private var awayDuringBreak = false

    @ObservationIgnored private var alertTimer: Timer?
    @ObservationIgnored private var breakTimer: Timer?

    /// - Parameters:
    ///   - now: injectable clock for tests.
    ///   - schedulesTimers: false in tests; then call `tick()` manually.
    init(now: @escaping () -> Date = Date.init, schedulesTimers: Bool = true) {
        self.now = now
        self.schedulesTimers = schedulesTimers
    }

    var isActive: Bool { status != .idle }

    // MARK: Control

    /// Start a new session. `snapshot`/`matched` describe what is frontmost right now.
    func start(snapshot: ActivitySnapshot?, matched: StudySpace?) {
        guard status == .idle else { return }
        let t = now()
        resetAccounting()
        sessionID = UUID()
        sessionStartedAt = t
        if let snapshot, !snapshot.isOwnApp { lastSnapshot = snapshot }
        lastMatched = matched
        if let matched {
            enterStudying(matched, at: t)
        } else {
            enterDistracted(at: t)
        }
        rescheduleTimers()
    }

    /// Manual pause. Stops accruing focused/distracted time.
    func pause() {
        enterPause(reason: .manual)
    }

    /// Pause for a break; auto-resumes after `duration`.
    func pause(for duration: TimeInterval) {
        enterPause(reason: .onBreak(until: now().addingTimeInterval(max(0, duration))))
    }

    /// Resume from any pause. The distraction timer always starts fresh.
    /// Caller should ingest a fresh snapshot right after.
    func resume() {
        guard status == .paused else { return }
        resumeFromPause(at: now())
        rescheduleTimers()
    }

    /// End the session. Returns (and emits via `onSessionEnded`) the finished record.
    @discardableResult
    func stop() -> StudySessionRecord? {
        guard status != .idle else { return nil }
        let t = now()
        let wasDistracted = status == .distracted
        let record = makeRecord(at: t)
        invalidateTimers()
        resetAccounting()
        if wasDistracted { onDistractionEnded?() }
        if let record { onSessionEnded?(record) }
        return record
    }

    /// Feed a new frontmost-activity snapshot. `matched` is the study space it falls in (or nil).
    /// Snapshots with `isOwnApp == true` are ignored (state is kept).
    func ingest(_ snapshot: ActivitySnapshot, matched: StudySpace?) {
        guard status != .idle, !snapshot.isOwnApp else { return }
        let t = now()
        lastSnapshot = snapshot
        lastMatched = matched

        switch status {
        case .studying:
            if let matched {
                if matched != currentSpace {
                    // Space switch: close the per-space segment, keep the focus streak running.
                    closeSegment(at: t)
                    currentSpace = matched
                    lastStudySpace = matched
                }
            } else {
                leaveStudying(at: t)
                enterDistracted(at: t)
                rescheduleTimers()
            }
        case .distracted:
            if let matched {
                let hadEpisode = endEpisode(at: t)
                enterStudying(matched, at: t)
                rescheduleTimers()
                if hadEpisode { onDistractionEnded?() }
            } else if episodeAppName == nil {
                episodeAppName = snapshot.appName
            }
        case .paused, .idle:
            break
        }
    }

    /// Screen locked / Mac asleep. Pauses with reason `.away` (unless already paused).
    func systemWentAway() {
        switch status {
        case .studying, .distracted:
            enterPause(reason: .away)
        case .paused:
            if case .onBreak = pauseReason { awayDuringBreak = true }
        case .idle:
            break
        }
    }

    /// Screen unlocked / Mac woke. Resumes only if the pause reason was `.away`.
    func systemReturned() {
        guard status == .paused else { return }
        let t = now()
        // A break that ran out while the Mac was away becomes a plain away pause first.
        _ = processBreakExpiry(at: t)
        if pauseReason == .away {
            resumeFromPause(at: t)
            rescheduleTimers()
        } else {
            awayDuringBreak = false
        }
    }

    /// Re-check the alert threshold and break expiry against the clock.
    func tick() {
        guard status != .idle else { return }
        let t = now()
        _ = processBreakExpiry(at: t)
        fireAlertIfDue(at: t)
        rescheduleTimers()
    }

    // MARK: Live readouts (pure functions of state + `date`)

    func focusedTime(at date: Date) -> TimeInterval {
        focusedAcc + openSegmentElapsed(.studying, at: date)
    }

    func distractedTime(at date: Date) -> TimeInterval {
        distractedAcc + openSegmentElapsed(.distracted, at: date)
    }

    func pausedTime(at date: Date) -> TimeInterval {
        pausedAcc + openSegmentElapsed(.paused, at: date)
    }

    /// Length of the current distraction episode; 0 when not distracted.
    func currentDistractionElapsed(at date: Date) -> TimeInterval {
        guard status == .distracted, let start = distractionStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    /// Length of the current uninterrupted studying stretch; 0 when not studying.
    func currentFocusStreak(at date: Date) -> TimeInterval {
        guard status == .studying, let start = streakStart else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    /// Remaining break time, or nil when not on a break.
    func breakRemaining(at date: Date) -> TimeInterval? {
        guard status == .paused, case .onBreak(let until)? = pauseReason else { return nil }
        return max(0, until.timeIntervalSince(date))
    }

    /// Snapshot of the running session as a record (for crash recovery and live UI). nil when idle.
    func liveRecord(at date: Date) -> StudySessionRecord? {
        makeRecord(at: date)
    }

    // MARK: Record building (pure)

    private func openSegmentElapsed(_ kind: SessionStatus, at date: Date) -> TimeInterval {
        guard status == kind, let start = segmentStart else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    private static func countsAsDistraction(duration: TimeInterval, triggeredAlert: Bool) -> Bool {
        // An episode that fired an alert always counts, even with a very short threshold.
        duration >= minimumDistractionDuration || triggeredAlert
    }

    private func makeRecord(at date: Date) -> StudySessionRecord? {
        guard status != .idle, let id = sessionID, let startedAt = sessionStartedAt else { return nil }

        var breakdown = spaceAcc
        if status == .studying, let name = currentSpace?.name {
            breakdown[name, default: 0] += openSegmentElapsed(.studying, at: date)
        }
        breakdown = breakdown.filter { $0.value > 0 }

        var distractions = events
        var count = distractionCount
        if status == .distracted, let start = distractionStartedAt {
            let duration = max(0, date.timeIntervalSince(start))
            let triggered = alertsInEpisode > 0
            if Self.countsAsDistraction(duration: duration, triggeredAlert: triggered) {
                distractions.append(DistractionEvent(start: start, duration: duration,
                                                     appName: episodeAppName, triggeredAlert: triggered))
                count += 1
            }
        }

        let longest = max(closedLongestStreak, currentFocusStreak(at: date))

        return StudySessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: max(date, startedAt),
            focusedSeconds: focusedTime(at: date),
            distractedSeconds: distractedTime(at: date),
            pausedSeconds: pausedTime(at: date),
            distractionCount: count,
            alertCount: alertCount,
            longestFocusStreak: longest,
            distractions: distractions,
            spaceBreakdown: breakdown
        )
    }

    // MARK: State transitions

    private func resetAccounting() {
        status = .idle
        pauseReason = nil
        sessionID = nil
        sessionStartedAt = nil
        currentSpace = nil
        lastStudySpace = nil
        lastSnapshot = nil
        distractionStartedAt = nil
        distractionCount = 0
        alertCount = 0
        focusedAcc = 0
        distractedAcc = 0
        pausedAcc = 0
        spaceAcc = [:]
        segmentStart = nil
        streakStart = nil
        closedLongestStreak = 0
        events = []
        episodeAppName = nil
        alertsInEpisode = 0
        alertAnchor = nil
        lastMatched = nil
        awayDuringBreak = false
    }

    /// Add the open segment (up to `t`) to the accumulator of the current status and restart it at `t`.
    private func closeSegment(at t: Date) {
        guard let start = segmentStart else { return }
        let elapsed = max(0, t.timeIntervalSince(start))
        switch status {
        case .studying:
            focusedAcc += elapsed
            if let name = currentSpace?.name { spaceAcc[name, default: 0] += elapsed }
        case .distracted:
            distractedAcc += elapsed
        case .paused:
            pausedAcc += elapsed
        case .idle:
            break
        }
        segmentStart = t
    }

    /// Close the studying segment and the focus streak. Caller sets the next status.
    private func leaveStudying(at t: Date) {
        closeSegment(at: t)
        if let start = streakStart {
            closedLongestStreak = max(closedLongestStreak, t.timeIntervalSince(start))
        }
        streakStart = nil
        currentSpace = nil
    }

    private func enterStudying(_ space: StudySpace, at t: Date) {
        status = .studying
        pauseReason = nil
        awayDuringBreak = false
        currentSpace = space
        lastStudySpace = space
        segmentStart = t
        streakStart = t
        distractionStartedAt = nil
    }

    private func enterDistracted(at t: Date) {
        status = .distracted
        pauseReason = nil
        awayDuringBreak = false
        currentSpace = nil
        segmentStart = t
        streakStart = nil
        distractionStartedAt = t
        episodeAppName = lastSnapshot?.appName
        alertsInEpisode = 0
        alertAnchor = nil
    }

    /// Close the open distraction episode (segment included) and record it. Returns true if one was open.
    @discardableResult
    private func endEpisode(at t: Date) -> Bool {
        guard status == .distracted, let start = distractionStartedAt else { return false }
        closeSegment(at: t)
        let duration = max(0, t.timeIntervalSince(start))
        let triggered = alertsInEpisode > 0
        if Self.countsAsDistraction(duration: duration, triggeredAlert: triggered) {
            events.append(DistractionEvent(start: start, duration: duration,
                                           appName: episodeAppName, triggeredAlert: triggered))
            distractionCount += 1
        }
        distractionStartedAt = nil
        episodeAppName = nil
        alertsInEpisode = 0
        alertAnchor = nil
        return true
    }

    private func enterPause(reason: PauseReason) {
        let t = now()
        switch status {
        case .studying:
            leaveStudying(at: t)
            beginPause(reason, at: t)
            rescheduleTimers()
        case .distracted:
            endEpisode(at: t)
            beginPause(reason, at: t)
            rescheduleTimers()
            onDistractionEnded?()
        case .paused:
            // Re-pausing just changes the reason (e.g. manual pause during a break).
            pauseReason = reason
            awayDuringBreak = false
            rescheduleTimers()
        case .idle:
            break
        }
    }

    private func beginPause(_ reason: PauseReason, at t: Date) {
        status = .paused
        pauseReason = reason
        awayDuringBreak = false
        segmentStart = t
        distractionStartedAt = nil
    }

    private func resumeFromPause(at t: Date) {
        closeSegment(at: t)
        if let space = lastMatched {
            enterStudying(space, at: t)
        } else {
            enterDistracted(at: t)
        }
    }

    /// Handles an expired break. Returns true if the session was resumed.
    @discardableResult
    private func processBreakExpiry(at t: Date) -> Bool {
        guard status == .paused, case .onBreak(let until)? = pauseReason, t >= until else { return false }
        if awayDuringBreak {
            // Still away: stay paused, but now `systemReturned()` is allowed to resume.
            pauseReason = .away
            awayDuringBreak = false
            return false
        }
        resumeFromPause(at: t)
        rescheduleTimers()
        onBreakEnded?()
        return true
    }

    // MARK: Alerts

    private func nextAlertDeadline() -> Date? {
        guard status == .distracted, let start = distractionStartedAt else { return nil }
        if alertsInEpisode == 0 { return start.addingTimeInterval(distractionThreshold) }
        guard let interval = repeatInterval, let anchor = alertAnchor else { return nil }
        return anchor.addingTimeInterval(interval)
    }

    private func fireAlertIfDue(at t: Date) {
        guard status == .distracted,
              let start = distractionStartedAt,
              let deadline = nextAlertDeadline(),
              t >= deadline else { return }

        // On time: stay on the regular grid. Late (clock jump): one alert only, next one counted from now.
        alertAnchor = t.timeIntervalSince(deadline) > Self.lateAlertTolerance ? t : deadline
        let isRepeat = alertsInEpisode > 0
        alertsInEpisode += 1
        alertCount += 1
        rescheduleTimers()

        let context = AlertContext(
            distractedFor: max(0, t.timeIntervalSince(start)),
            distractingAppName: lastSnapshot?.appName ?? episodeAppName,
            lastStudySpace: lastStudySpace,
            isRepeat: isRepeat
        )
        onAlert?(context)
    }

    // MARK: Timers

    private func invalidateTimers() {
        alertTimer?.invalidate()
        alertTimer = nil
        breakTimer?.invalidate()
        breakTimer = nil
    }

    /// (Re)schedules one-shot timers for exactly the next deadlines. Called on every state change.
    private func rescheduleTimers() {
        invalidateTimers()
        guard schedulesTimers, status != .idle else { return }
        let t = now()
        if let deadline = nextAlertDeadline() {
            alertTimer = makeTimer(after: deadline.timeIntervalSince(t))
        }
        if status == .paused, case .onBreak(let until)? = pauseReason {
            breakTimer = makeTimer(after: until.timeIntervalSince(t))
        }
    }

    private func makeTimer(after interval: TimeInterval) -> Timer {
        let timer = Timer(timeInterval: max(0.01, interval), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
