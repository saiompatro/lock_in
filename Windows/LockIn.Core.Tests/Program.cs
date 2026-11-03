using LockIn.Core;

// Dependency-free executable tests: failures exit nonzero, locally and in CI.
var tests = new (string Name, Action Body)[]
{
    ("App match ignores case", () => Check(new StudySpace("Notes", "Notepad").Matches("notepad", "Anything"))),
    ("App match rejects another process", () => Check(!new StudySpace("Notes", "notepad").Matches("msedge", "Notepad"))),
    ("Window keyword requires matching app and title", () =>
    {
        var space = new StudySpace("Lecture", "msedge", "  Lecture 4  ");
        Check(space.Matches("MSEdge", "LECTURE 4 - Notes"));
        Check(!space.Matches("msedge", "Video"));
        Check(!space.Matches("chrome", "Lecture 4"));
    }),
    ("Switches close timestamp segments", () => WithClock((engine, advance) =>
    {
        engine.Start(true); advance(60); engine.Ingest(false); advance(30);
        var record = engine.Stop()!;
        Equal(60, record.FocusedSeconds); Equal(30, record.DistractedSeconds); Equal(0, record.PausedSeconds);
        Check(engine.Status == SessionStatus.Idle);
    })),
    ("Own windows are neutral", () => WithClock((engine, advance) =>
    {
        engine.Start(true); advance(15); engine.Ingest(false, ownApp: true); advance(15);
        Equal(30, engine.FocusedSeconds); Equal(0, engine.DistractedSeconds);
    })),
    ("Threshold fires once and repeats on schedule", () => WithClock((engine, advance) =>
    {
        engine.Start(false); advance(299); Check(!engine.Tick()); advance(1); Check(engine.Tick());
        Check(!engine.Tick()); advance(300); Check(engine.Tick()); Equal(2, engine.Alerts);
    })),
    ("Delayed ticks do not spam", () => WithClock((engine, advance) =>
    {
        engine.Start(false); advance(20000); Check(engine.Tick()); Check(!engine.Tick()); Equal(1, engine.Alerts);
    })),
    ("Disabled repeat fires once", () => WithClock((engine, advance) =>
    {
        engine.Repeat = null; engine.Start(false); advance(300); Check(engine.Tick()); advance(9999); Check(!engine.Tick());
    })),
    ("Return resets distraction deadline", () => WithClock((engine, advance) =>
    {
        engine.Start(false); advance(299); engine.Ingest(true); advance(30); engine.Ingest(false);
        advance(299); Check(!engine.Tick()); advance(1); Check(engine.Tick());
    })),
    ("Pause accrues only paused time", () => WithClock((engine, advance) =>
    {
        engine.Start(true); advance(60); engine.Pause(); advance(120); Check(!engine.Tick());
        engine.Resume(); advance(60); var r = engine.Stop()!;
        Equal(120, r.FocusedSeconds); Equal(120, r.PausedSeconds); Equal(0, r.DistractedSeconds);
    })),
    ("Break resumes with fresh match", () => WithClock((engine, advance) =>
    {
        engine.Start(false); engine.Pause(PauseReason.Break, TimeSpan.FromMinutes(5)); engine.Ingest(true);
        advance(300); Check(!engine.Tick()); Check(engine.Status == SessionStatus.Studying);
    })),
    ("Expired break waits for unlock", () => WithClock((engine, advance) =>
    {
        engine.Start(true); engine.Pause(PauseReason.Break, TimeSpan.FromMinutes(5)); engine.SetAway(true);
        advance(600); engine.Tick(); Check(engine.Reason == PauseReason.Away);
        engine.SetAway(false); Check(engine.Status == SessionStatus.Studying);
    })),
    ("Unlock preserves manual pause", () => WithClock((engine, _) =>
    {
        engine.Start(true); engine.Pause(); engine.SetAway(true); engine.SetAway(false);
        Check(engine.Status == SessionStatus.Paused && engine.Reason == PauseReason.Manual);
    })),
    ("Cannot resume while locked", () => WithClock((engine, _) =>
    {
        engine.Start(true); engine.SetAway(true); engine.Resume(); Check(engine.Status == SessionStatus.Paused);
        engine.SetAway(false); Check(engine.Status == SessionStatus.Studying);
    })),
    ("Restart clears accounting and reminders", () => WithClock((engine, advance) =>
    {
        engine.Start(false); advance(300); engine.Tick(); engine.Stop(); engine.Start(true);
        Equal(0, engine.Alerts); Equal(0, engine.FocusedSeconds); Equal(0, engine.DistractedSeconds);
    })),
    ("Changed threshold applies to active episode", () => WithClock((engine, advance) =>
    {
        engine.Start(false); advance(60); engine.Threshold = TimeSpan.FromSeconds(30); Check(engine.Tick());
        engine.Repeat = null; advance(1000); Check(!engine.Tick());
        engine.Repeat = TimeSpan.FromSeconds(60); advance(60); Check(engine.Tick());
    })),
    ("Snapshot keeps stable identity without stopping", () => WithClock((engine, advance) =>
    {
        engine.Start(true); advance(20); var first = engine.Snapshot()!; advance(20); var second = engine.Snapshot()!;
        Check(first.Id == second.Id && engine.Active); Equal(20, first.FocusedSeconds); Equal(40, second.FocusedSeconds);
    }))
};
foreach (var test in tests)
{
    try { test.Body(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception e) { Console.Error.WriteLine($"FAIL {test.Name}: {e.Message}"); Environment.Exit(1); }
}
Console.WriteLine($"{tests.Length} tests passed.");
static void Check(bool value) { if (!value) throw new Exception("Assertion failed"); }
static void Equal(double expected, double actual) { if (Math.Abs(expected - actual) > .001) throw new Exception($"Expected {expected}, got {actual}"); }
static void WithClock(Action<SessionEngine, Action<int>> body)
{
    var time = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
    body(new SessionEngine(() => time), seconds => time = time.AddSeconds(seconds));
}
