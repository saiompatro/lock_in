using System.Text.Json;
using LockIn.Core;

namespace LockIn.Windows;

internal sealed class LocalStore
{
    public static string DirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lock In");
    public List<StudySpace> Spaces { get; } = Load<List<StudySpace>>("study-spaces.json") ?? [];
    public List<SessionRecord> Sessions { get; } = Load<List<SessionRecord>>("sessions.json") ?? [];
    public Preferences Preferences { get; } = Load<Preferences>("settings.json") ?? new();

    public LocalStore()
    {
        var interrupted = Load<SessionRecord>("live-session.json");
        if (interrupted is not null)
        {
            AddSession(interrupted);
            File.Delete(Path.Combine(DirectoryPath, "live-session.json"));
        }
    }
    public void SaveSpaces() => Save("study-spaces.json", Spaces);
    public void SavePreferences() => Save("settings.json", Preferences);
    public void AddSession(SessionRecord record)
    {
        Sessions.RemoveAll(s => s.Id == record.Id);
        Sessions.Insert(0, record);
        Save("sessions.json", Sessions);
    }
    public void DeleteHistory()
    {
        Sessions.Clear();
        Save("sessions.json", Sessions);
        File.Delete(Path.Combine(DirectoryPath, "live-session.json"));
    }
    public static void SaveLive(SessionRecord? record)
    {
        if (record is not null) Save("live-session.json", record);
        else File.Delete(Path.Combine(DirectoryPath, "live-session.json"));
    }
    private static T? Load<T>(string name)
    {
        var path = Path.Combine(DirectoryPath, name);
        if (!File.Exists(path)) return default;
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path)); }
        catch (JsonException)
        {
            // Preserve the original file and stop rather than silently replacing the user's data.
            throw new InvalidDataException($"Cannot read {name}. Back up and repair or move this file before restarting.");
        }
    }
    private static void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(DirectoryPath);
        var target = Path.Combine(DirectoryPath, name);
        var temporary = target + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, target, overwrite: true);
    }
}
