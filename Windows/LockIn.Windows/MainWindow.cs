using System.Diagnostics;
using System.Media;
using Microsoft.Win32;
using LockIn.Core;

namespace LockIn.Windows;

internal sealed class MainWindow : Form
{
    private readonly LocalStore store = new();
    private readonly SessionEngine engine = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    private readonly NotifyIcon tray;
    private readonly Label status = new() { AutoSize = true, Font = new Font("Segoe UI", 22, FontStyle.Bold) };
    private readonly Label totals = new() { AutoSize = true };
    private readonly Label today = new() { AutoSize = true };
    private readonly ListBox spaces = new() { Dock = DockStyle.Fill, IntegralHeight = false };
    private readonly ListView history = new() { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true };
    private readonly Button start = new() { Text = "Start session", AutoSize = true };
    private readonly Button pause = new() { Text = "Pause", AutoSize = true, Enabled = false };
    private readonly Button stop = new() { Text = "End session", AutoSize = true, Enabled = false };
    private readonly NumericUpDown threshold = new() { Minimum = 1, Maximum = 120, Width = 90 };
    private readonly NumericUpDown repeat = new() { Minimum = 0, Maximum = 120, Width = 90 };
    private readonly CheckBox sound = new() { Text = "Play a reminder sound", AutoSize = true };
    private Form? reminder;
    private bool quitting, locked, suspended;
    private DateTimeOffset lastSave;

    public MainWindow()
    {
        Text = "Lock In";
        Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application;
        MinimumSize = new Size(760, 560);
        Size = new Size(900, 660);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(246, 248, 251);
        var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(20, 12) };
        Controls.Add(tabs);
        var overview = Page(tabs, "Overview");
        var stack = Stack();
        overview.Controls.Add(stack);
        stack.Controls.Add(Heading("Make room for focus."));
        stack.Controls.Add(Note("Choose your study spaces, start a session, and settle in. Lock In will remind you when you drift away."));
        stack.Controls.Add(status);
        stack.Controls.Add(totals);
        stack.Controls.Add(today);
        var actions = Row();
        actions.Controls.AddRange([start, pause, stop]);
        stack.Controls.Add(actions);
        stack.Controls.Add(Note("Closing this window keeps Lock In in the system tray. Use the tray menu to quit."));
        start.Click += (_, _) => StartSession();
        pause.Click += (_, _) => { if (engine.Status == SessionStatus.Paused) { Sample(); engine.Resume(); } else engine.Pause(); RefreshState(); };
        stop.Click += (_, _) => EndSession();

        var spacePage = Page(tabs, "Study spaces");
        var spaceLayout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, Padding = new Padding(20) };
        spaceLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        spaceLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        spaceLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        spaceLayout.Controls.Add(Note("Allow an entire app or a window title keyword. For websites, choose your browser and a distinctive tab title keyword."), 0, 0);
        spaceLayout.Controls.Add(spaces, 0, 1);
        var spaceActions = Row();
        spaceActions.Controls.Add(ActionButton("Add study space", AddSpace));
        spaceActions.Controls.Add(ActionButton("Remove selected", () =>
        {
            if (spaces.SelectedIndex < 0) return;
            store.Spaces.RemoveAt(spaces.SelectedIndex);
            store.SaveSpaces();
            RefreshSpaces();
        }));
        spaceLayout.Controls.Add(spaceActions, 0, 2);
        spacePage.Controls.Add(spaceLayout);
        RefreshSpaces();

        var historyPage = Page(tabs, "History");
        history.Columns.Add("Started", 200);
        history.Columns.Add("Focused", 130);
        history.Columns.Add("Distracted", 130);
        history.Columns.Add("Paused", 130);
        history.Columns.Add("Reminders", 100);
        historyPage.Controls.Add(history);
        RefreshHistory();

        var settingsPage = Page(tabs, "Settings & privacy");
        var settings = Stack();
        settingsPage.Controls.Add(settings);
        settings.Controls.Add(Heading("Your pace. Your data."));
        settings.Controls.Add(Note("Remind me after this many minutes outside my study spaces:"));
        threshold.Value = Math.Clamp(store.Preferences.ThresholdMinutes, 1, 120);
        settings.Controls.Add(threshold);
        settings.Controls.Add(Note("Repeat reminders every N minutes (0 sends one reminder per distraction):"));
        repeat.Value = Math.Clamp(store.Preferences.RepeatMinutes, 0, 120);
        settings.Controls.Add(repeat);
        sound.Checked = store.Preferences.Sound;
        settings.Controls.Add(sound);
        threshold.ValueChanged += (_, _) => SaveSettings();
        repeat.ValueChanged += (_, _) => SaveSettings();
        sound.CheckedChanged += (_, _) => SaveSettings();
        settings.Controls.Add(ActionButton("Test reminder", () => ShowReminder(true)));
        settings.Controls.Add(Note("Tracking runs only during a session. Locking Windows or sleeping pauses it automatically.\nNo account, analytics, network requests, keystroke capture, or browser history access.\nStored locally: your chosen spaces, preferences, and session totals. Detected titles are never saved."));
        settings.Controls.Add(ActionButton("Open local data folder", () =>
        {
            Directory.CreateDirectory(LocalStore.DirectoryPath);
            Process.Start(new ProcessStartInfo("explorer.exe", LocalStore.DirectoryPath) { UseShellExecute = true });
        }));
        settings.Controls.Add(ActionButton("Delete all session history", () =>
        {
            if (engine.Active) { MessageBox.Show(this, "End the current session before deleting history.", Text); return; }
            if (MessageBox.Show(this, "Permanently delete all session history? Study spaces and preferences will be kept.",
                Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            store.DeleteHistory();
            RefreshHistory();
            RefreshState();
        }));
        ApplySettings();

        var menu = new ContextMenuStrip();
        menu.Items.Add("Open Lock In", null, (_, _) => Reveal());
        menu.Items.Add("Start session", null, (_, _) => StartSession());
        menu.Items.Add("Take a 5-minute break", null, (_, _) => TakeBreak());
        menu.Items.Add("End session", null, (_, _) => EndSession());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => { quitting = true; Close(); });
        tray = new NotifyIcon { Icon = Icon, Text = "Lock In", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => Reveal();
        tray.BalloonTipClicked += (_, _) => Reveal();
        timer.Tick += (_, _) => Tick();
        Load += (_, _) =>
        {
            SystemEvents.SessionSwitch += SessionChanged;
            SystemEvents.PowerModeChanged += PowerChanged;
            timer.Start();
        };
        FormClosing += (_, e) =>
        {
            if (!quitting && e.CloseReason == CloseReason.UserClosing)
            { e.Cancel = true; Hide(); return; }
            quitting = true;
            timer.Stop();
            SystemEvents.SessionSwitch -= SessionChanged;
            SystemEvents.PowerModeChanged -= PowerChanged;
            EndSession();
            tray.Visible = false;
            tray.Dispose();
            timer.Dispose();
        };
        RefreshState();
    }

    internal void Quit() { quitting = true; Close(); }

    private void StartSession()
    {
        if (engine.Active) return;
        if (store.Spaces.Count == 0) { Reveal(); MessageBox.Show(this, "Add at least one study space first.", Text); return; }
        ApplySettings();
        engine.Start(false);
        engine.SetAway(locked || suspended);
        Sample();
        lastSave = DateTimeOffset.UtcNow;
        LocalStore.SaveLive(engine.Snapshot());
        RefreshState();
    }
    private void EndSession()
    {
        if (engine.Stop() is { } record) store.AddSession(record);
        LocalStore.SaveLive(null);
        CloseReminder();
        RefreshHistory();
        RefreshState();
    }
    private void Sample()
    {
        if (!engine.Active) return;
        var snapshot = ForegroundWindow.Read();
        engine.Ingest(snapshot is not null && store.Spaces.Any(s => s.Matches(snapshot.ProcessName, snapshot.Title)), snapshot?.OwnApp == true);
    }
    private void Tick()
    {
        if (!engine.Active) return;
        Sample();
        if (engine.Tick()) ShowReminder();
        if (engine.Status != SessionStatus.Distracted) CloseReminder();
        if ((DateTimeOffset.UtcNow - lastSave).TotalSeconds >= 30)
        { LocalStore.SaveLive(engine.Snapshot()); lastSave = DateTimeOffset.UtcNow; }
        RefreshState();
    }
    private void SessionChanged(object sender, SessionSwitchEventArgs e) => OnUi(() =>
    {
        if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.SessionLogoff or SessionSwitchReason.ConsoleDisconnect or SessionSwitchReason.RemoteDisconnect) locked = true;
        else if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.SessionLogon or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect) locked = false;
        UpdateAway();
    });
    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => OnUi(() =>
    {
        if (e.Mode == PowerModes.Suspend) suspended = true;
        else if (e.Mode == PowerModes.Resume) suspended = false;
        UpdateAway();
    });
    private void OnUi(Action action) { if (!quitting && IsHandleCreated && !IsDisposed) BeginInvoke(action); }
    private void UpdateAway() { Sample(); engine.SetAway(locked || suspended); if (engine.Status == SessionStatus.Paused) CloseReminder(); RefreshState(); }
    private void TakeBreak() { engine.Pause(PauseReason.Break, TimeSpan.FromMinutes(5)); CloseReminder(); RefreshState(); }
    private void SaveSettings() { store.Preferences.ThresholdMinutes = (int)threshold.Value; store.Preferences.RepeatMinutes = (int)repeat.Value; store.Preferences.Sound = sound.Checked; store.SavePreferences(); ApplySettings(); }
    private void ApplySettings() { engine.Threshold = TimeSpan.FromMinutes((int)threshold.Value); engine.Repeat = repeat.Value == 0 ? null : TimeSpan.FromMinutes((int)repeat.Value); }
    private void RefreshState()
    {
        status.Text = engine.Status switch { SessionStatus.Idle => "Ready when you are", SessionStatus.Studying => "Studying", SessionStatus.Distracted => $"Away from study spaces · {Duration(engine.DistractionElapsed)}", _ => $"Paused · {engine.Reason}" };
        totals.Text = engine.Active ? $"Focused {Duration(engine.FocusedSeconds)}    Distracted {Duration(engine.DistractedSeconds)}    Paused {Duration(engine.PausedSeconds)}" : "Start a session to begin tracking.";
        var daily = store.Sessions.Where(s => s.StartedAt.LocalDateTime.Date == DateTime.Today).Sum(s => s.FocusedSeconds) + (engine.Active ? engine.FocusedSeconds : 0);
        today.Text = $"Today's focused time: {Duration(daily)}";
        start.Enabled = !engine.Active;
        stop.Enabled = pause.Enabled = engine.Active;
        pause.Text = engine.Status == SessionStatus.Paused ? "Resume" : "Pause";
        if (tray is not null) tray.Text = ("Lock In · " + engine.Status);
    }
    private void RefreshSpaces() { spaces.Items.Clear(); spaces.Items.AddRange(store.Spaces.Cast<object>().ToArray()); }
    private void RefreshHistory()
    {
        history.Items.Clear();
        foreach (var s in store.Sessions.OrderByDescending(s => s.StartedAt))
            history.Items.Add(new ListViewItem([s.StartedAt.LocalDateTime.ToString("g"), Duration(s.FocusedSeconds), Duration(s.DistractedSeconds), Duration(s.PausedSeconds), s.Alerts.ToString()]));
    }
    private void Reveal() { Show(); WindowState = FormWindowState.Normal; Activate(); }
    private void CloseReminder() { reminder?.Close(); reminder = null; }
    private void ShowReminder(bool preview = false)
    {
        if (reminder is not null) return;
        if (sound.Checked) SystemSounds.Exclamation.Play();
        tray.ShowBalloonTip(5000, "Time to lock in", "Return to one of your study spaces or take a short break.", ToolTipIcon.Info);
        reminder = new Form { Text = preview ? "Lock In · Test reminder" : "Time to lock in", Size = new Size(520, 290), MinimumSize = new Size(520, 290), StartPosition = FormStartPosition.CenterScreen, TopMost = true, Font = Font, Icon = Icon };
        var content = Stack();
        content.Controls.Add(Heading("Come back to your focus."));
        content.Controls.Add(Note("You've been away from your study spaces.\nReady to get back, or need a moment to recharge?"));
        var buttons = Row();
        buttons.Controls.Add(ActionButton("Dismiss", CloseReminder));
        if (!preview)
        {
            buttons.Controls.Add(ActionButton("5-minute break", TakeBreak));
            buttons.Controls.Add(ActionButton("End session", EndSession));
        }
        content.Controls.Add(buttons);
        reminder.Controls.Add(content);
        reminder.FormClosed += (_, _) => reminder = null;
        reminder.Show();
    }

    private void AddSpace()
    {
        using var dialog = new Form { Text = "Add study space", Size = new Size(580, 430), MinimumSize = new Size(580, 430), StartPosition = FormStartPosition.CenterParent, Font = Font };
        var layout = Stack();
        dialog.Controls.Add(layout);
        var name = new TextBox { Width = 470, PlaceholderText = "Name, e.g. Lecture notes" };
        var processName = new TextBox { Width = 470, PlaceholderText = "Process name without .exe, e.g. msedge" };
        var keyword = new TextBox { Width = 470, PlaceholderText = "Optional title keyword, e.g. Notion" };
        var windows = new ComboBox { Width = 470, DropDownStyle = ComboBoxStyle.DropDownList, DisplayMember = "Title" };
        var candidates = new List<(string Process, string Title)>();
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try { if (process.Id != Environment.ProcessId && !string.IsNullOrWhiteSpace(process.MainWindowTitle)) candidates.Add((process.ProcessName, process.MainWindowTitle)); }
                catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
            }
        }
        windows.Items.AddRange(candidates.Select(c => (object)$"{c.Process} · {c.Title}").ToArray());
        windows.SelectedIndexChanged += (_, _) =>
        {
            var c = candidates[windows.SelectedIndex];
            processName.Text = c.Process;
            if (string.IsNullOrWhiteSpace(name.Text)) name.Text = c.Process;
        };
        layout.Controls.Add(Note("Pick an open app or enter its process name:"));
        layout.Controls.Add(windows);
        layout.Controls.Add(name);
        layout.Controls.Add(processName);
        layout.Controls.Add(keyword);
        layout.Controls.Add(Note("Leave the keyword empty to allow the whole app.\nWebsite matching uses the visible tab title, not the URL.\nOnly the text you enter here is saved."));
        var save = ActionButton("Add space", () =>
        {
            var process = processName.Text.Trim();
            if (process.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) process = process[..^4];
            if (string.IsNullOrWhiteSpace(name.Text) || string.IsNullOrWhiteSpace(process) || process.IndexOfAny(['/', '\\', ':']) >= 0)
            { MessageBox.Show(dialog, "Enter a name and a process name (not a file path).", "Add study space"); return; }
            var space = new StudySpace(name.Text.Trim(), process, keyword.Text.Trim());
            if (!store.Spaces.Contains(space)) { store.Spaces.Add(space); store.SaveSpaces(); RefreshSpaces(); }
            dialog.DialogResult = DialogResult.OK;
        });
        layout.Controls.Add(save);
        dialog.AcceptButton = save;
        dialog.ShowDialog(this);
    }

    private static string Duration(double seconds) => TimeSpan.FromSeconds(Math.Max(0, seconds)).ToString(@"hh\:mm\:ss");
    private static FlowLayoutPanel Stack() => new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(24) };
    private static FlowLayoutPanel Row() => new() { AutoSize = true, Margin = new Padding(0, 12, 0, 12) };
    private static Label Heading(string text) => new() { Text = text, AutoSize = true, Font = new Font("Segoe UI", 22, FontStyle.Bold), Margin = new Padding(0, 0, 0, 16) };
    private static Label Note(string text) => new() { Text = text, AutoSize = true, MaximumSize = new Size(720, 0), Margin = new Padding(0, 8, 0, 14) };
    private static Button ActionButton(string text, Action action) { var button = new Button { Text = text, AutoSize = true, Padding = new Padding(8, 4, 8, 4) }; button.Click += (_, _) => action(); return button; }
    private static TabPage Page(TabControl tabs, string title) { var page = new TabPage(title) { UseVisualStyleBackColor = true }; tabs.TabPages.Add(page); return page; }
}
