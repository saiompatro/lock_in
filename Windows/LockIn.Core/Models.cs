namespace LockIn.Core;

public sealed record StudySpace(string Name, string ProcessName, string TitleKeyword = "")
{
    public bool Matches(string processName, string title) =>
        string.Equals(ProcessName, processName, StringComparison.OrdinalIgnoreCase) &&
        (string.IsNullOrWhiteSpace(TitleKeyword) ||
         title.Contains(TitleKeyword.Trim(), StringComparison.OrdinalIgnoreCase));
    public override string ToString() => string.IsNullOrWhiteSpace(TitleKeyword)
        ? $"{Name} · {ProcessName}" : $"{Name} · {ProcessName} · title: {TitleKeyword}";
}

public enum SessionStatus { Idle, Studying, Distracted, Paused }
public enum PauseReason { Manual, Break, Away }
public sealed record SessionRecord(Guid Id, DateTimeOffset StartedAt, DateTimeOffset EndedAt,
    double FocusedSeconds, double DistractedSeconds, double PausedSeconds, int Alerts);
public sealed class Preferences
{
    public int ThresholdMinutes { get; set; } = 5;
    public int RepeatMinutes { get; set; } = 5;
    public bool Sound { get; set; } = true;
}
