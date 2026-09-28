using System.Security.Principal;
using System.Windows;
using System.Windows.Threading;

namespace HateVPN.Desktop;

public partial class App : Application
{
    private Mutex? _mutex;
    private EventWaitHandle? _show;
    private RegisteredWaitHandle? _registration;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        bool preview = e.Args.Length >= 2 && e.Args[0] == "--render-preview";
        if (!preview)
        {
            var sid = WindowsIdentity.GetCurrent().User!.Value;
            _mutex = new Mutex(true, @"Local\HateVPN.UI." + sid, out var created);
            if (!created)
            {
                try { using var other = EventWaitHandle.OpenExisting(@"Local\HateVPN.Show." + sid); other.Set(); } catch { }
                Shutdown(); return;
            }
            _show = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\HateVPN.Show." + sid);
            _registration = ThreadPool.RegisterWaitForSingleObject(_show, (_, _) => Dispatcher.BeginInvoke(() => (MainWindow as MainWindow)?.RestoreWindow()), null, Timeout.Infinite, false);
        }
        var window = new MainWindow(preview); MainWindow = window;
        SessionEnding += (_, _) => window.AllowSessionEnd();
        if (preview)
        {
            window.WindowStartupLocation = WindowStartupLocation.Manual; window.Left = -10000; window.Top = -10000;
            window.ShowActivated = false; window.ShowInTaskbar = false; window.Show();
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            window.RenderPreview(e.Args[1], e.Args.Contains("--connected"), e.Args.Contains("--profiles"), e.Args.Contains("--vps"), e.Args.Contains("--settings"), e.Args.Contains("--empty"), e.Args.Contains("--subscription"), e.Args.Contains("--switch"), e.Args.Contains("--sample-input"), e.Args.Contains("--invites")); window.Close(); return;
        }
        window.Show();
    }
    protected override void OnExit(ExitEventArgs e)
    {
        _registration?.Unregister(null); _show?.Dispose(); _mutex?.Dispose(); base.OnExit(e);
    }
}
