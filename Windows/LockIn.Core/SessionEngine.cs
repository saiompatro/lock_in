namespace LockIn.Core;

// No OS dependencies. All transitions close timestamp-based segments; delayed ticks don't lose time.
public sealed class SessionEngine(Func<DateTimeOffset>? clock = null)
{
    private readonly Func<DateTimeOffset> now = clock ?? (() => DateTimeOffset.UtcNow);
    private DateTimeOffset started, segment, episode, nextAlert;
    private DateTimeOffset? breakUntil;
    private readonly double[] totals = new double[4];
    private Guid id;
    private bool matched, away;
    private int episodeAlerts;
    private TimeSpan threshold = TimeSpan.FromMinutes(5);
    private TimeSpan? repeat = TimeSpan.FromMinutes(5);
    public SessionStatus Status { get; private set; }
    public PauseReason? Reason { get; private set; }
    public int Alerts { get; private set; }
    public TimeSpan Threshold
    {
        get => threshold;
        set
        {
            threshold = value > TimeSpan.Zero ? value : TimeSpan.FromSeconds(1);
            if (Status == SessionStatus.Distracted && episodeAlerts == 0) nextAlert = episode + threshold;
        }
    }
    public TimeSpan? Repeat
    {
        get => repeat;
        set
        {
            if (repeat == value) return;
            repeat = value;
            if (Status == SessionStatus.Distracted && episodeAlerts > 0)
                nextAlert = value is { } interval && interval > TimeSpan.Zero ? now() + interval : DateTimeOffset.MaxValue;
        }
    }
    public bool Active => Status != SessionStatus.Idle;
    public double FocusedSeconds => Seconds(SessionStatus.Studying);
    public double DistractedSeconds => Seconds(SessionStatus.Distracted);
    public double PausedSeconds => Seconds(SessionStatus.Paused);
    public double DistractionElapsed => Status == SessionStatus.Distracted ? Elapsed(episode) : 0;

    public void Start(bool isMatch)
    {
        if (Active) return;
        Array.Clear(totals);
        Alerts = 0;
        id = Guid.NewGuid();
        started = segment = now();
        matched = isMatch;
        away = false;
        Transition(isMatch ? SessionStatus.Studying : SessionStatus.Distracted);
    }

    public void Ingest(bool isMatch, bool ownApp = false)
    {
        if (!Active || ownApp) return;
        matched = isMatch;
        if (Status != SessionStatus.Paused)
            Transition(isMatch ? SessionStatus.Studying : SessionStatus.Distracted);
    }

    public void Pause(PauseReason reason = PauseReason.Manual, TimeSpan? duration = null)
    {
        if (!Active) return;
        Transition(SessionStatus.Paused);
        Reason = reason;
        breakUntil = reason == PauseReason.Break ? now() + (duration ?? TimeSpan.FromMinutes(5)) : null;
    }

    public void Resume()
    {
        if (Status != SessionStatus.Paused || away) return;
        Transition(matched ? SessionStatus.Studying : SessionStatus.Distracted);
        Reason = null;
        breakUntil = null;
    }

    public void SetAway(bool value)
    {
        away = value;
        if (!Active) return;
        if (value && Status != SessionStatus.Paused) Pause(PauseReason.Away);
        else if (!value && Reason == PauseReason.Away) Resume();
    }

    // At most one alert per tick, even if a delayed tick crosses several repeat deadlines.
    public bool Tick()
    {
        if (Status == SessionStatus.Paused && Reason == PauseReason.Break && now() >= breakUntil)
        {
            if (away) { Reason = PauseReason.Away; breakUntil = null; }
            else Resume();
        }
        if (Status != SessionStatus.Distracted || now() < nextAlert) return false;
        Alerts++;
        episodeAlerts++;
        nextAlert = Repeat is { } interval && interval > TimeSpan.Zero
            ? now() + interval : DateTimeOffset.MaxValue;
        return true;
    }

    public SessionRecord? Snapshot() => !Active ? null : new(id, started, now(),
        FocusedSeconds, DistractedSeconds, PausedSeconds, Alerts);

    public SessionRecord? Stop()
    {
        var record = Snapshot();
        Status = SessionStatus.Idle;
        Reason = null;
        breakUntil = null;
        return record;
    }

    private void Transition(SessionStatus next)
    {
        if (Status == next) return;
        if (Active) totals[(int)Status] += Elapsed(segment);
        Status = next;
        segment = now();
        if (next == SessionStatus.Distracted)
        {
            episode = segment;
            episodeAlerts = 0;
            nextAlert = segment + Threshold;
        }
    }
    private double Seconds(SessionStatus state) => totals[(int)state] + (Status == state ? Elapsed(segment) : 0);
    private double Elapsed(DateTimeOffset since) => Math.Max(0, (now() - since).TotalSeconds);
}
