import Testing
import Foundation

// SessionEngine.swift is compiled directly into this target (no host app, no @testable import).

@MainActor
private final class FakeClock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
private final class Recorder {
    var alerts: [AlertContext] = []
    var distractionEnded = 0
    var breakEnded = 0
    var records: [StudySessionRecord] = []
}

@MainActor
private struct Harness {
    let clock = FakeClock()
    let engine: SessionEngine
    let rec = Recorder()

    let notes = StudySpace(kind: .app, name: "Notes", bundleID: "com.example.notes")
    let docs = StudySpace(kind: .website, name: "docs.example.com", urlPattern: "docs.example.com")

    init(threshold: TimeInterval = 300, repeatInterval: TimeInterval? = 300) {
        let clock = self.clock
        engine = SessionEngine(now: { clock.date }, schedulesTimers: false)
        engine.distractionThreshold = threshold
        engine.repeatInterval = repeatInterval
        let rec = self.rec
        engine.onAlert = { rec.alerts.append($0) }
        engine.onDistractionEnded = { rec.distractionEnded += 1 }
        engine.onBreakEnded = { rec.breakEnded += 1 }
        engine.onSessionEnded = { rec.records.append($0) }
    }

    func snap(_ app: String, own: Bool = false) -> ActivitySnapshot {
        ActivitySnapshot(timestamp: clock.date, bundleID: "com.example.\(app.lowercased())",
                         appName: app, isOwnApp: own)
    }

    /// Advance the clock by `seconds` and tick.
    func run(_ seconds: TimeInterval) {
        clock.advance(seconds)
        engine.tick()
    }

    func goTo(_ app: String, in space: StudySpace?) {
        engine.ingest(snap(app), matched: space)
    }

    var t: Date { clock.date }
}

@MainActor
struct SessionEngineTests {

    // MARK: Start

    @Test func startInsideSpaceIsStudying() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        #expect(h.engine.status == .studying)
        #expect(h.engine.currentSpace == h.notes)
        #expect(h.engine.lastStudySpace == h.notes)
        #expect(h.engine.distractionStartedAt == nil)
        #expect(h.engine.sessionID != nil)
        h.run(60)
        #expect(h.engine.focusedTime(at: h.t) == 60)
        #expect(h.engine.currentFocusStreak(at: h.t) == 60)
    }

    @Test func startOutsideSpaceStartsDistractionTimer() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Safari"), matched: nil)
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionStartedAt == h.t)
        h.run(42)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 42)
        #expect(h.engine.distractedTime(at: h.t) == 42)
        #expect(h.engine.focusedTime(at: h.t) == 0)
        #expect(h.engine.lastStudySpace == nil)
    }

    @Test func switchingBetweenSpacesNeverStartsDistraction() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.goTo("Safari", in: h.docs)
        #expect(h.engine.status == .studying)
        #expect(h.engine.currentSpace == h.docs)
        #expect(h.engine.lastStudySpace == h.docs)
        #expect(h.engine.distractionStartedAt == nil)
        h.run(100)
        h.goTo("Notes", in: h.notes)
        #expect(h.engine.status == .studying)
        // Focus streak runs across space switches.
        #expect(h.engine.currentFocusStreak(at: h.t) == 200)
        #expect(h.rec.distractionEnded == 0)
        #expect(h.engine.distractionCount == 0)
    }

    // MARK: Distraction timer

    @Test func leavingStartsTimerAndReturningResetsIt() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(60)
        h.goTo("Safari", in: nil)
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionStartedAt == h.t)
        h.run(120)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 120)

        h.goTo("Notes", in: h.notes)
        #expect(h.engine.status == .studying)
        #expect(h.engine.distractionStartedAt == nil)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 0)
        #expect(h.rec.distractionEnded == 1)
        #expect(h.engine.distractionCount == 1)

        // Leaving again starts from zero, so 200 s later there is still no alert.
        h.goTo("Safari", in: nil)
        h.run(200)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 200)
        #expect(h.rec.alerts.isEmpty)
    }

    @Test func movingBetweenDistractingAppsKeepsEpisodeRunning() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(100)
        h.goTo("Music", in: nil)
        h.run(100)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 200)
        h.goTo("Notes", in: h.notes)
        let record = h.engine.stop()
        // Episode is attributed to the app that started it.
        #expect(record?.distractions.first?.appName == "Safari")
    }

    // MARK: Alerts

    @Test func alertFiresExactlyOnceAtThreshold() {
        let h = Harness(threshold: 300, repeatInterval: nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(299)
        #expect(h.rec.alerts.isEmpty)
        h.run(1)
        #expect(h.rec.alerts.count == 1)
        #expect(h.engine.alertCount == 1)
        let ctx = h.rec.alerts[0]
        #expect(ctx.distractedFor == 300)
        #expect(ctx.distractingAppName == "Safari")
        #expect(ctx.lastStudySpace == h.notes)
        #expect(ctx.isRepeat == false)

        // Further ticks and a lot of time: nil repeat interval means once per episode.
        for _ in 0..<10 { h.run(300) }
        #expect(h.rec.alerts.count == 1)
    }

    @Test func alertRepeatsEveryRepeatInterval() {
        let h = Harness(threshold: 300, repeatInterval: 120)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(300)
        #expect(h.rec.alerts.count == 1)
        h.run(119)
        #expect(h.rec.alerts.count == 1)
        h.run(1)
        #expect(h.rec.alerts.count == 2)
        #expect(h.rec.alerts[1].isRepeat)
        #expect(h.rec.alerts[1].distractedFor == 420)
        h.run(120)
        #expect(h.rec.alerts.count == 3)
        #expect(h.engine.alertCount == 3)

        // A new episode starts the cycle again with a non-repeat alert.
        h.goTo("Notes", in: h.notes)
        h.goTo("Safari", in: nil)
        h.run(300)
        #expect(h.rec.alerts.count == 4)
        #expect(h.rec.alerts[3].isRepeat == false)
    }

    @Test func noAlertSpamAfterBigClockJump() {
        let h = Harness(threshold: 300, repeatInterval: 300)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(300)
        #expect(h.rec.alerts.count == 1)

        // Mac slept for ~an hour without away events: many repeat deadlines passed, one alert only.
        h.run(3600)
        #expect(h.rec.alerts.count == 2)
        h.run(1)
        h.run(1)
        #expect(h.rec.alerts.count == 2)
        // The next one is scheduled from the jump, not from the old grid.
        h.run(297)
        #expect(h.rec.alerts.count == 2)
        h.run(1)
        #expect(h.rec.alerts.count == 3)
    }

    @Test func bigJumpPastFirstThresholdFiresOnce() {
        let h = Harness(threshold: 300, repeatInterval: 300)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(10_000)
        #expect(h.rec.alerts.count == 1)
        h.run(1)
        #expect(h.rec.alerts.count == 1)
    }

    @Test func changingThresholdMidEpisodeTakesEffect() {
        let h = Harness(threshold: 300, repeatInterval: nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(100)
        h.engine.distractionThreshold = 120
        h.run(19)
        #expect(h.rec.alerts.isEmpty)
        h.run(1)
        #expect(h.rec.alerts.count == 1)
    }

    @Test func changingRepeatIntervalMidEpisodeTakesEffect() {
        let h = Harness(threshold: 60, repeatInterval: 600)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(60)
        #expect(h.rec.alerts.count == 1)
        h.engine.repeatInterval = 90
        h.run(90)
        #expect(h.rec.alerts.count == 2)
    }

    @Test func alertedEpisodeIsMarkedTriggered() {
        let h = Harness(threshold: 20, repeatInterval: nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(20)
        h.run(10)
        h.goTo("Notes", in: h.notes)
        let record = h.engine.stop()
        #expect(record?.distractions.count == 1)
        #expect(record?.distractions.first?.triggeredAlert == true)
        #expect(record?.distractions.first?.duration == 30)
        #expect(record?.alertCount == 1)
    }

    // MARK: Short episodes

    @Test func shortEpisodesAreNotCountedButTimeIs() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(60)
        h.goTo("Safari", in: nil)
        h.run(10)
        h.goTo("Notes", in: h.notes)
        #expect(h.engine.distractionCount == 0)
        #expect(h.rec.distractionEnded == 1)
        h.run(60)
        h.goTo("Mail", in: nil)
        h.run(15)
        h.goTo("Notes", in: h.notes)
        #expect(h.engine.distractionCount == 1)

        let record = h.engine.stop()
        #expect(record?.distractionCount == 1)
        #expect(record?.distractions.count == 1)
        #expect(record?.distractedSeconds == 25)
        #expect(record?.focusedSeconds == 120)
    }

    @Test func openEpisodeAtStopCountsOnlyIfLongEnough() {
        let short = Harness()
        short.engine.start(snapshot: short.snap("Notes"), matched: short.notes)
        short.goTo("Safari", in: nil)
        short.run(14)
        let shortRecord = short.engine.stop()
        #expect(shortRecord?.distractionCount == 0)
        #expect(shortRecord?.distractedSeconds == 14)

        let long = Harness()
        long.engine.start(snapshot: long.snap("Notes"), matched: long.notes)
        long.goTo("Safari", in: nil)
        long.run(15)
        let longRecord = long.engine.stop()
        #expect(longRecord?.distractionCount == 1)
        #expect(longRecord?.distractions.first?.duration == 15)
        #expect(long.rec.distractionEnded == 1)
    }

    // MARK: Pause / resume

    @Test func pauseStopsAccrualAndEndsEpisode() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.goTo("Safari", in: nil)
        h.run(60)
        h.engine.pause()
        #expect(h.engine.status == .paused)
        #expect(h.engine.pauseReason == .manual)
        #expect(h.engine.distractionStartedAt == nil)
        #expect(h.rec.distractionEnded == 1)
        #expect(h.engine.distractionCount == 1)

        let focused = h.engine.focusedTime(at: h.t)
        let distracted = h.engine.distractedTime(at: h.t)
        h.run(600)
        #expect(h.engine.focusedTime(at: h.t) == focused)
        #expect(h.engine.distractedTime(at: h.t) == distracted)
        #expect(h.engine.pausedTime(at: h.t) == 600)
        #expect(h.engine.currentFocusStreak(at: h.t) == 0)
        #expect(h.rec.alerts.isEmpty)
    }

    @Test func resumeStartsFreshDistractionTimer() {
        let h = Harness(threshold: 300, repeatInterval: nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.goTo("Safari", in: nil)
        h.run(250)
        h.engine.pause()
        h.run(1000)
        h.engine.resume()
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionStartedAt == h.t)
        h.run(299)
        #expect(h.rec.alerts.isEmpty)
        h.run(1)
        #expect(h.rec.alerts.count == 1)
    }

    @Test func resumeUsesIngestedMatchWhilePaused() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Safari"), matched: nil)
        h.engine.pause()
        // While paused the engine records activity but accrues nothing.
        h.run(30)
        h.goTo("Notes", in: h.notes)
        #expect(h.engine.status == .paused)
        #expect(h.engine.lastSnapshot?.appName == "Notes")
        #expect(h.engine.focusedTime(at: h.t) == 0)
        h.engine.resume()
        #expect(h.engine.status == .studying)
        #expect(h.engine.currentSpace == h.notes)
        #expect(h.engine.currentFocusStreak(at: h.t) == 0)
    }

    // MARK: Breaks

    @Test func breakAutoResumesViaTick() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(60)
        h.engine.pause(for: 300)
        #expect(h.engine.status == .paused)
        #expect(h.engine.breakRemaining(at: h.t) == 300)
        h.run(100)
        #expect(h.engine.breakRemaining(at: h.t) == 200)
        #expect(h.rec.breakEnded == 0)
        h.run(199)
        #expect(h.engine.status == .paused)
        h.run(1)
        #expect(h.engine.status == .studying)
        #expect(h.engine.breakRemaining(at: h.t) == nil)
        #expect(h.rec.breakEnded == 1)
        #expect(h.engine.pausedTime(at: h.t) == 300)
    }

    @Test func breakEndingWhileOutsideSpaceStartsFreshDistraction() {
        let h = Harness(threshold: 300, repeatInterval: nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.engine.pause(for: 60)
        h.goTo("Safari", in: nil)
        h.run(60)
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionStartedAt == h.t)
        h.run(300)
        #expect(h.rec.alerts.count == 1)
        #expect(h.rec.alerts.first?.distractingAppName == "Safari")
    }

    @Test func manualResumeDuringBreakCancelsExpiry() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.engine.pause(for: 300)
        h.run(10)
        h.engine.resume()
        #expect(h.engine.status == .studying)
        h.run(1000)
        #expect(h.rec.breakEnded == 0)
        #expect(h.engine.status == .studying)
    }

    // MARK: Away

    @Test func awayPausesAndReturnedResumes() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.engine.systemWentAway()
        #expect(h.engine.status == .paused)
        #expect(h.engine.pauseReason == .away)
        h.run(500)
        h.engine.systemReturned()
        #expect(h.engine.status == .studying)
        #expect(h.engine.pausedTime(at: h.t) == 500)
        #expect(h.engine.focusedTime(at: h.t) == 100)
    }

    @Test func awayWhileDistractedEndsEpisode() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Safari"), matched: nil)
        h.run(30)
        h.engine.systemWentAway()
        #expect(h.rec.distractionEnded == 1)
        h.run(1000)
        h.engine.systemReturned()
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionStartedAt == h.t)
    }

    @Test func manualPauseIsNotResumedBySystemReturned() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.engine.pause()
        h.engine.systemWentAway()
        #expect(h.engine.pauseReason == .manual)
        h.run(10)
        h.engine.systemReturned()
        #expect(h.engine.status == .paused)
        #expect(h.engine.pauseReason == .manual)
    }

    @Test func systemReturnedDuringBreakKeepsBreak() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.engine.pause(for: 300)
        h.engine.systemWentAway()
        h.run(100)
        h.engine.systemReturned()
        #expect(h.engine.status == .paused)
        #expect(h.engine.breakRemaining(at: h.t) == 200)
    }

    @Test func breakExpiringWhileAwayResumesOnReturn() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.engine.pause(for: 60)
        h.engine.systemWentAway()
        h.run(120)
        // Break is over but the Mac is still locked: stay paused, no distraction.
        #expect(h.engine.status == .paused)
        h.engine.systemReturned()
        #expect(h.engine.status == .studying)
        #expect(h.engine.pausedTime(at: h.t) == 120)
    }

    // MARK: Own app

    @Test func ownAppSnapshotsAreNeutral() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(30)
        h.engine.ingest(h.snap("Lock In", own: true), matched: nil)
        #expect(h.engine.status == .studying)
        #expect(h.engine.lastSnapshot?.appName == "Notes")
        h.run(30)
        #expect(h.engine.focusedTime(at: h.t) == 60)

        // And while distracted, an own-app snapshot (even one that matches nothing) keeps the episode.
        h.goTo("Safari", in: nil)
        h.run(20)
        h.engine.ingest(h.snap("Lock In", own: true), matched: h.notes)
        #expect(h.engine.status == .distracted)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 20)
        #expect(h.engine.lastSnapshot?.appName == "Safari")
    }

    // MARK: Stop / records

    @Test func stopTotalsAddUpToWallTime() {
        let h = Harness()
        let began = h.t
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)                       // focused 100
        h.goTo("Safari", in: nil)
        h.run(40)                        // distracted 40
        h.goTo("Notes", in: h.notes)
        h.run(250)                       // focused 250 (longest streak)
        h.engine.pause()
        h.run(70)                        // paused 70
        h.engine.resume()
        h.goTo("Notes", in: h.notes)
        h.run(30)                        // focused 30
        h.engine.pause(for: 600)
        h.run(50)                        // paused 50 (break still running)
        h.goTo("Mail", in: nil)
        h.engine.resume()
        h.run(25)                        // distracted 25

        let end = h.t
        let record = h.engine.stop()
        #expect(record != nil)
        guard let record else { return }
        #expect(record.startedAt == began)
        #expect(record.endedAt == end)
        #expect(record.focusedSeconds == 380)
        #expect(record.distractedSeconds == 65)
        #expect(record.pausedSeconds == 120)
        let sum = record.focusedSeconds + record.distractedSeconds + record.pausedSeconds
        #expect(sum == end.timeIntervalSince(began))
        #expect(record.longestFocusStreak == 250)
        #expect(record.distractionCount == 2)
        #expect(record.distractions.map(\.appName) == ["Safari", "Mail"])

        // Delivered and engine reset.
        #expect(h.rec.records.count == 1)
        #expect(h.rec.records.first?.id == record.id)
        #expect(h.engine.status == .idle)
        #expect(h.engine.sessionID == nil)
        #expect(h.engine.alertCount == 0)
        #expect(h.engine.focusedTime(at: h.t) == 0)
        #expect(h.engine.stop() == nil)
    }

    @Test func stopWhilePausedAccountsPausedTime() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(10)
        h.engine.pause()
        h.run(20)
        let record = h.engine.stop()
        #expect(record?.focusedSeconds == 10)
        #expect(record?.pausedSeconds == 20)
        #expect(record?.distractedSeconds == 0)
    }

    @Test func longestStreakIncludesRunningStreak() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.goTo("Safari", in: nil)
        h.run(20)
        h.goTo("Notes", in: h.notes)
        h.run(300)
        let record = h.engine.stop()
        #expect(record?.longestFocusStreak == 300)
    }

    @Test func spaceBreakdownSplitsFocusedTimeBySpace() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.goTo("Safari", in: h.docs)
        h.run(50)
        h.goTo("Mail", in: nil)
        h.run(30)
        h.goTo("Notes", in: h.notes)
        h.run(25)
        let record = h.engine.stop()
        #expect(record?.spaceBreakdown["Notes"] == 125)
        #expect(record?.spaceBreakdown["docs.example.com"] == 50)
        #expect(record?.spaceBreakdown.count == 2)
        let total = record?.spaceBreakdown.values.reduce(0, +)
        #expect(total == record?.focusedSeconds)
    }

    // MARK: liveRecord

    @Test func liveRecordDoesNotMutateState() {
        let h = Harness(threshold: 300, repeatInterval: nil)
        #expect(h.engine.liveRecord(at: h.t) == nil)
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(100)
        h.goTo("Safari", in: nil)
        h.run(40)

        let live = h.engine.liveRecord(at: h.t)
        #expect(live?.focusedSeconds == 100)
        #expect(live?.distractedSeconds == 40)
        #expect(live?.distractionCount == 1)
        #expect(live?.distractions.first?.appName == "Safari")
        #expect(live?.endedAt == h.t)

        // State untouched: still distracted, same episode, nothing delivered.
        #expect(h.engine.status == .distracted)
        #expect(h.engine.distractionCount == 0)
        #expect(h.engine.currentDistractionElapsed(at: h.t) == 40)
        #expect(h.rec.records.isEmpty)
        #expect(h.rec.distractionEnded == 0)

        // Calling it for a later date works as "if stopped then" and stays pure.
        let later = h.engine.liveRecord(at: h.t.addingTimeInterval(60))
        #expect(later?.distractedSeconds == 100)
        #expect(h.engine.distractedTime(at: h.t) == 40)
        #expect(h.engine.liveRecord(at: h.t)?.id == live?.id)
    }

    @Test func liveRecordIncludesPausedAndStreak() {
        let h = Harness()
        h.engine.start(snapshot: h.snap("Notes"), matched: h.notes)
        h.run(90)
        let live = h.engine.liveRecord(at: h.t)
        #expect(live?.longestFocusStreak == 90)
        #expect(live?.spaceBreakdown["Notes"] == 90)
        h.engine.pause()
        h.run(10)
        #expect(h.engine.liveRecord(at: h.t)?.pausedSeconds == 10)
    }
}
