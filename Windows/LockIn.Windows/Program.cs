using LockIn.Core;

namespace LockIn.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool smokeTest = args.Contains("--smoke-test");
        using var mutex = new Mutex(true, "Local\\LockIn.Windows", out bool firstInstance);
        if (!firstInstance) { if (!smokeTest) MessageBox.Show("Lock In is already running. Open it from the system tray.", "Lock In"); return 1; }
        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
        try
        {
            using var window = new MainWindow();
            using var startupTimer = new System.Windows.Forms.Timer { Interval = 1500 };
            if (smokeTest)
            {
                startupTimer.Tick += (_, _) => { startupTimer.Stop(); window.Quit(); };
                window.Shown += (_, _) => startupTimer.Start();
            }
            Application.Run(window);
            return 0;
        }
        catch (Exception error)
        {
            if (smokeTest) { Console.Error.WriteLine(error); return 1; }
            MessageBox.Show($"Lock In could not continue. Your saved files are in:\n{LocalStore.DefaultDirectoryPath}\n\n{error.Message}",
                "Lock In", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
