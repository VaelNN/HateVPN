using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace HateVPN.Setup;

public partial class App : Application
{
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var preview = e.Args.Length >= 2 && e.Args[0] == "--render-preview";
        var window = new MainWindow(preview);
        MainWindow = window;
        if (preview)
        {
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -10000; window.Top = -10000;
            window.ShowActivated = false; window.ShowInTaskbar = false;
            window.Show();
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            window.RenderPreview(e.Args[1], e.Args.Length > 2 ? e.Args[2] : "setup");
            window.Close();
            return;
        }
        window.Show();
    }
}
