using System.Text.Json;

namespace LockIn.Core;

public sealed class LocalStore
{
    public static string DefaultDirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lock In");
    public string DirectoryPath { get; }
    public List<StudySpace> Spaces { get; }
    public List<SessionRecord> Sessions { get; }
    public Preferences Preferences { get; }

    public LocalStore(string? directoryPath = null)
    {
        DirectoryPath = directoryPath ?? DefaultDirectoryPath;
        Spaces = Load<List<StudySpace>>("study-spaces.json") ?? [];
        Sessions = Load<List<SessionRecord>>("sessions.json") ?? [];
        Preferences = Load<Preferences>("settings.json") ?? new();
        var interrupted = Load<SessionRecord>("live-session.json");
        if (interrupted is not null)
        {
            AddSession(interrupted);
            RemoveLive();
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
        RemoveLive();
    }
    public void SaveLive(SessionRecord? record)
    {
        if (record is not null) Save("live-session.json", record);
        else RemoveLive();
    }
    private void RemoveLive()
    {
        var path = Path.Combine(DirectoryPath, "live-session.json");
        if (File.Exists(path)) File.Delete(path);
    }
    private T? Load<T>(string name)
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
    private void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(DirectoryPath);
        var target = Path.Combine(DirectoryPath, name);
        var temporary = target + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, target, overwrite: true);
    }
}
