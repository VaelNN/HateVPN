using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using Microsoft.Win32;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace HateVPN.Setup;

public partial class MainWindow : Window
{
    private readonly bool _preview;
    private bool _wantVideo = true;
    private bool _installing;
    private bool _installed;
    private string? _installedPath;
    private string? _workingDirectory;

    public MainWindow(bool preview = false)
    {
        _preview = preview;
        InitializeComponent();
        InstallPathBox.Text = PreferredInstallPath();
        Loaded += (_, _) => { if (!_preview) StartVideo(); };
        Closing += OnClosing;
        InstallerVideo.Volume = .12;
    }

    private string WorkingDirectory => _workingDirectory ??= CreateWorkingDirectory();

    private static string CreateWorkingDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), "HateVPN-Setup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void CopyResource(string name, string destination)
    {
        using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new IOException("Не найдены файлы установки HateVPN.");
        using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        resource.CopyTo(output);
    }

    private void StartVideo()
    {
        try
        {
            var path = Path.Combine(WorkingDirectory, "installer-video.mp4");
            CopyResource("HateVPN.Setup.Video.mp4", path);
            InstallerVideo.Source = new Uri(path);
            InstallerVideo.Play();
        }
        catch
        {
            VideoButton.IsEnabled = false;
            VideoButton.Content = "Недоступно";
        }
    }

    private void Video_MediaOpened(object sender, RoutedEventArgs e)
    {
        if (_wantVideo) InstallerVideo.Play();
    }

    private void Video_MediaEnded(object sender, RoutedEventArgs e)
    {
        InstallerVideo.Position = TimeSpan.Zero;
        if (_wantVideo) InstallerVideo.Play();
    }

    private void Video_MediaFailed(object sender, ExceptionRoutedEventArgs e)
    {
        VideoButton.IsEnabled = false;
        VideoButton.Content = "Недоступно";
    }

    private void Video_Click(object sender, RoutedEventArgs e)
    {
        _wantVideo = !_wantVideo;
        if (_wantVideo) InstallerVideo.Play(); else InstallerVideo.Pause();
        VideoButton.Content = _wantVideo ? "Пауза" : "Включить";
    }

    private void Volume_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (InstallerVideo is null || VolumeValue is null || VolumeSlider is null) return;
        InstallerVideo.Volume = VolumeSlider.Value / 100;
        VolumeValue.Text = $"{VolumeSlider.Value:0}%";
    }

    private static string PreferredInstallPath()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"Software\HateVPN");
            if (key?.GetValue("InstallPath") is string saved && !string.IsNullOrWhiteSpace(saved))
                return saved.TrimEnd(Path.DirectorySeparatorChar);
        }
        catch {   }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "HateVPN");
    }

    private static string ValidInstallPath(string entered)
    {
        entered = entered.Trim().Trim('"');
        if (string.IsNullOrWhiteSpace(entered) || !Path.IsPathFullyQualified(entered) || entered.StartsWith(@"\\", StringComparison.Ordinal))
            throw new FormatException("Выберите папку на локальном диске, например C:\\Program Files\\HateVPN.");
        var path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(entered));
        var root = Path.GetPathRoot(path) ?? throw new FormatException("Неверный путь установки.");
        var drive = new DriveInfo(root);
        if (!drive.IsReady || drive.DriveType != DriveType.Fixed || path.Equals(Path.TrimEndingDirectorySeparator(root), StringComparison.OrdinalIgnoreCase))
            throw new FormatException("Выберите отдельную папку на локальном диске.");
        var windowsFolder = Path.TrimEndingDirectorySeparator(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
        if (path.Equals(windowsFolder, StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith(windowsFolder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new FormatException("Выберите отдельную папку для HateVPN, не системную папку Windows.");
        foreach (var protectedFolder in new[] {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData) })
        {
            if (path.Equals(Path.TrimEndingDirectorySeparator(protectedFolder), StringComparison.OrdinalIgnoreCase))
                throw new FormatException("Выберите отдельную папку для HateVPN.");
        }
        if (File.Exists(path)) throw new FormatException("По выбранному пути уже находится файл. Выберите папку.");
        return path;
    }

    private void BrowseInstallPath_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Выберите папку установки HateVPN", Multiselect = false };
        try
        {
            var current = InstallPathBox.Text.Trim();
            var initial = Directory.Exists(current) ? current : Path.GetDirectoryName(current);
            if (initial is not null && Directory.Exists(initial)) dialog.InitialDirectory = initial;
        }
        catch {   }
        if (dialog.ShowDialog(this) == true) InstallPathBox.Text = dialog.FolderName;
    }

    private async void Install_Click(object sender, RoutedEventArgs e)
    {
        if (_installing) return;
        if (_installed)
        {
            Open_Click(sender, e);
            return;
        }

        string installPath;
        try { installPath = ValidInstallPath(InstallPathBox.Text); }
        catch (Exception ex) when (ex is ArgumentException or FormatException or IOException or UnauthorizedAccessException)
        { StatusText.Text = ex.Message; InstallPathBox.Focus(); return; }

        _installing = true;
        InstallButton.IsEnabled = false;
        DesktopShortcutCheck.IsEnabled = false;
        InstallPathBox.IsEnabled = false;
        BrowseInstallPathButton.IsEnabled = false;
        CloseButton.IsEnabled = false;
        StatusText.Text = "";
        SetupPanel.Visibility = Visibility.Collapsed;
        InstallingPanel.Visibility = Visibility.Visible;
        InstallStageText.Text = "Подготавливаем файлы…";
        var msiPath = Path.Combine(WorkingDirectory, "HateVPN.msi");
        try
        {
            await Task.Run(() => CopyResource("HateVPN.Setup.Payload.msi", msiPath));
            var logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HateVPN");
            Directory.CreateDirectory(logDirectory);
            var logPath = Path.Combine(logDirectory, "setup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
            var desktop = DesktopShortcutCheck.IsChecked == true ? "1" : "0";
            var start = new ProcessStartInfo("msiexec.exe")
            {
                UseShellExecute = true,
                Verb = "runas",

                Arguments = $"/i \"{msiPath}\" /qn /norestart DESKTOPSHORTCUT={desktop} INSTALLFOLDER=\"{installPath}\" /L*v \"{logPath}\""
            };
            InstallStageText.Text = "Устанавливаем HateVPN…";
            using var process = Process.Start(start) ?? throw new IOException("Не удалось запустить установку Windows.");
            await process.WaitForExitAsync();
            if (process.ExitCode is not (0 or 3010))
                throw new IOException($"Установка завершилась с кодом {process.ExitCode}. Отчёт: {logPath}");
            _installed = true;
            _installedPath = installPath;
            InstallingPanel.Visibility = Visibility.Collapsed;
            SuccessPanel.Visibility = Visibility.Visible;
            RestartText.Visibility = process.ExitCode == 3010 ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        { ShowInstallError("Установка отменена. Можно повторить."); }
        catch (Exception ex)
        { ShowInstallError(ex.Message); }
        finally
        {
            try { File.Delete(msiPath); } catch { }
            _installing = false;
            InstallButton.IsEnabled = true;
            DesktopShortcutCheck.IsEnabled = !_installed;
            InstallPathBox.IsEnabled = !_installed;
            BrowseInstallPathButton.IsEnabled = !_installed;
            CloseButton.IsEnabled = true;
        }
    }

    private void ShowInstallError(string message)
    {
        InstallingPanel.Visibility = Visibility.Collapsed;
        SetupPanel.Visibility = Visibility.Visible;
        StatusText.Text = message;
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var app = Path.Combine(_installedPath ?? PreferredInstallPath(), "App", "HateVPN.exe");
            Process.Start(new ProcessStartInfo(app) { UseShellExecute = true });
            Close();
        }
        catch { OpenErrorText.Text = "Не удалось открыть HateVPN. Запустите его через меню «Пуск»."; }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_installing) { e.Cancel = true; return; }
        InstallerVideo.Stop();
        InstallerVideo.Source = null;
        if (_workingDirectory is not null)
        {
            try { Directory.Delete(_workingDirectory, recursive: true); } catch { }
        }
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        for (var element = e.OriginalSource as DependencyObject; element is not null; element = VisualTreeHelper.GetParent(element))
        {
            if (element is System.Windows.Controls.Button) return;
            if (ReferenceEquals(element, sender)) break;
        }
        DragMove();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    internal void RenderPreview(string path, string stage = "setup")
    {
        if (stage == "success")
        {
            SetupPanel.Visibility = Visibility.Collapsed;
            SuccessPanel.Visibility = Visibility.Visible;
        }
        else if (stage == "installing")
        {
            SetupPanel.Visibility = Visibility.Collapsed;
            InstallingPanel.Visibility = Visibility.Visible;
        }
        var image = new RenderTargetBitmap(760, 520, 96, 96, PixelFormats.Pbgra32);
        Measure(new Size(760, 520)); Arrange(new Rect(0, 0, 760, 520)); UpdateLayout();
        image.Render(this);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var file = File.Create(Path.GetFullPath(path));
        encoder.Save(file);
    }
}
