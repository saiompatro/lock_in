using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace LockIn.Windows;

internal sealed record WindowSnapshot(string ProcessName, string Title, bool OwnApp);
internal static class ForegroundWindow
{
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(nint window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);

    public static WindowSnapshot? Read()
    {
        var window = GetForegroundWindow();
        if (window == 0 || IsIconic(window) || !IsWindowVisible(window)) return null;
        GetWindowThreadProcessId(window, out uint processId);
        if (processId == Environment.ProcessId) return new("LockIn", "", true);
        try
        {
            using var process = Process.GetProcessById((int)processId);
            var title = new StringBuilder(2048);
            GetWindowText(window, title, title.Capacity);
            return new(process.ProcessName, title.ToString(), false);
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
        { return null; }
    }
}
