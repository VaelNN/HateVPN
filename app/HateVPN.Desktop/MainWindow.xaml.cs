using HateVPN.Core;
using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace HateVPN.Desktop;

public partial class MainWindow : Window
{
    private readonly BrokerClient _client = new();
    private readonly ProfileStore _store = new();
    private readonly SystemProxyLease _proxyLease = new();
    private readonly UserSettings _settings = UserSettings.Load();
    private ProfileData _profiles = new();
    private Snapshot _state = new("off");
    private readonly DispatcherTimer _poll = new() { Interval = TimeSpan.FromSeconds(2) };
    private ConnectivityResult? _connectivity;
    private string? _connectivityProfileId;
    private bool _checkingConnectivity;
    private long _connectivitySession;
    private CancellationTokenSource? _connectivityCancellation;
    private long _connectStartedAt;
    private TimeSpan? _tunnelStartTime, _siteReadyTime;
    private Forms.NotifyIcon? _tray;
    private Forms.ToolStripMenuItem? _trayConnect;
    private bool _busy, _polling, _serviceReady, _storageOk = true, _exitRequested, _shownTrayHint, _bindingSettings, _vpsUseKey, _inviteUseKey;
    private readonly bool _preview;
    private string? _connectionAction;
    private string? _subscriptionUrlOpen;
    private Button? _subscriptionReturnButton;
    private Profile? Selected => _profiles.Profiles.FirstOrDefault(p => p.Id == _profiles.SelectedId);
    private bool HasTunnel => _state.ProfileId is not null && _state.Owned;

    public MainWindow(bool preview = false)
    {
        _preview = preview;
        InitializeComponent();
        var availableHeight = Math.Max(300, SystemParameters.WorkArea.Height - 32);
        if (availableHeight < Height) { Height = availableHeight; Width = availableHeight * 480 / 760; }
        Loaded += async (_, _) =>
        {
            if (_preview) return;
            if (SystemParameters.ClientAreaAnimation) DesignSurface.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(280)));
            try { _profiles = _store.Load(); }
            catch { _storageOk = false; ShowError("Не удалось открыть хранилище профилей. Файл сохранён без изменений. Проверьте учётную запись Windows или восстановите резервную копию."); }
            RefreshProfiles();
            CreateTray();
            _poll.Tick += async (_, _) => await PollAsync();
            _poll.Start();
            await PollAsync();
            if (_state.Phase == "off") _proxyLease.Release();
            if (Environment.GetCommandLineArgs().Contains("--background")) Hide();
        };
        Closing += OnClosing;
        Closed += (_, _) => { _poll.Stop(); _tray?.Dispose(); };
    }

    private void CreateTray()
    {
        _tray = new Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "HateVPN · Не подключено", Visible = true
        };
        var menu = new Forms.ContextMenuStrip { BackColor = System.Drawing.Color.FromArgb(24, 22, 27), ForeColor = System.Drawing.Color.White, ShowImageMargin = false };
        menu.Items.Add("Открыть HateVPN", null, (_, _) => RestoreWindow());
        _trayConnect = new Forms.ToolStripMenuItem("Подключиться", null, async (_, _) => await ToggleAsync());
        menu.Items.Add(_trayConnect);
        menu.Items.Add("Настройки", null, (_, _) => { RestoreWindow(); OpenSettings(); });
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Выйти", null, async (_, _) => await ExitAsync());
        _tray.ContextMenuStrip = menu;
        _tray.DoubleClick += (_, _) => RestoreWindow();
    }

    public void RestoreWindow() { Show(); WindowState = WindowState.Normal; Activate(); }
    public void AllowSessionEnd() => _exitRequested = true;

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_preview || _exitRequested) return;
        e.Cancel = true;
        if (_settings.CloseToTray)
        {
            Hide();
            if (!_shownTrayHint && _tray is not null)
            { _shownTrayHint = true; _tray.ShowBalloonTip(2500, "HateVPN работает в трее", "Открыть или отключить VPN можно через значок рядом с часами.", Forms.ToolTipIcon.Info); }
        }
        else _ = ExitAsync();
    }

    private async Task ExitAsync()
    {
        if (_busy) return;
        _busy = true;
        try
        {

            if ((_serviceReady && _state.Owned) || HasTunnel)
            {
                var response = await _client.SendAsync(new("disconnect"));
                if (!response.Success) { RestoreWindow(); ShowError(response.Error!); return; }
                _proxyLease.Release();
            }
            _exitRequested = true;
            Close();
        }
        catch { RestoreWindow(); ShowError("Не удалось отключить VPN перед выходом. Проверьте службу HateVPNBroker и повторите выход."); }
        finally { _busy = false; }
    }

    private async Task PollAsync()
    {
        if (_polling || _busy || _preview) return;
        _polling = true;
        try
        {
            var response = await _client.SendAsync(new("status"));
            _serviceReady = response.Success;
            if (response.State?.Phase == "off" && _state.Phase != "off") ResetConnectivity();
            if (response.State is not null) _state = response.State;
            if (_state.Phase == "off") _proxyLease.Release();
            if (_state.Phase is not ("connecting" or "reconnecting" or "connected" or "no-data") || _state.Engine == "Xray" || !_state.FullTunnel)
            { _connectivity = null; _connectivityProfileId = null; }
            else if (!_checkingConnectivity &&
                (_connectivityProfileId != _state.ProfileId || _connectivity is null ||
                 DateTime.UtcNow - _connectivity.CheckedAt > TimeSpan.FromSeconds(_connectivity.Success ? 12 : 8)))
                _ = CheckConnectivityAsync();
        }
        catch { _serviceReady = false; }
        finally { _polling = false; UpdateState(); }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e) => await ToggleAsync();

    private async void DisconnectCurrent_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || !HasTunnel || _preview) return;
        ResetConnectivity();
        _busy = true; _connectionAction = "disconnect"; UpdateState();
        try
        {
            var response = await _client.SendAsync(new("disconnect"));
            if (!response.Success) { RestoreWindow(); ShowError(response.Error ?? "Не удалось отключить VPN."); }
            if (response.State is not null) _state = response.State;
            if (response.Success) _proxyLease.Release();
        }
        catch { RestoreWindow(); ShowError("Служба не ответила вовремя. Проверяем состояние подключения."); }
        finally { _busy = false; _connectionAction = null; await PollAsync(); }
    }

    private async Task ToggleAsync()
    {
        if (_busy || _preview) return;
        if (!HasTunnel && Selected is null) { RestoreWindow(); OpenProfiles(); return; }
        if (!_serviceReady) { RestoreWindow(); ShowError("Установите HateVPN через установщик. Если приложение уже установлено, запустите службу HateVPNBroker в службах Windows."); return; }
        var switching = HasTunnel && Selected is not null && Selected.Id != _state.ProfileId;
        var disconnecting = HasTunnel && !switching;
        ResetConnectivity();
        if (!disconnecting)
        {
            _connectStartedAt = Stopwatch.GetTimestamp();
            _tunnelStartTime = null; _siteReadyTime = null;
        }
        _busy = true;
        _connectionAction = switching ? "switch" : disconnecting ? "disconnect" : "connect";
        ConnectButton.IsEnabled = false;
        ErrorBanner.Visibility = Visibility.Collapsed;
        UpdateState();
        try
        {
            if (switching)
            {
                var stopped = await _client.SendAsync(new("disconnect"));
                if (!stopped.Success)
                {
                    RestoreWindow(); ShowError(stopped.Error ?? "Не удалось отключить предыдущий сервер.");
                    if (stopped.State is not null) _state = stopped.State;
                    return;
                }
                if (stopped.State is not null) _state = stopped.State;
                _proxyLease.Release();
            }
            var request = disconnecting ? new Request("disconnect") : new Request("connect", Selected!.Config, Selected.Id);
            var response = await _client.SendAsync(request);
            if (request.Command == "connect") _tunnelStartTime = Stopwatch.GetElapsedTime(_connectStartedAt);
            if (!response.Success) { RestoreWindow(); ShowError(response.Error ?? "Не удалось подключиться."); }
            if (response.State is not null) _state = response.State;
            if (response.Success && request.Command == "connect" && _state.Engine == "Xray")
            {
                try { _proxyLease.Acquire(); }
                catch (Exception ex)
                {
                    try { await _client.SendAsync(new("disconnect")); } catch {   }
                    _proxyLease.Release();
                    RestoreWindow();
                    ShowError("Не удалось включить системный прокси Windows: " + ex.Message);
                }
            }
            if (response.Success && request.Command == "connect" && _state.Engine != "Xray" && _state.FullTunnel)
                _ = CheckConnectivityAsync();
            if (response.Success && request.Command == "disconnect") _proxyLease.Release();
        }
        catch { RestoreWindow(); ShowError("Служба не ответила вовремя. Проверяем фактическое состояние подключения."); }
        finally { _busy = false; _connectionAction = null; await PollAsync(); }
    }

    private void UpdateState()
    {
        var needsProbe = _state.Phase == "connected" && _state.Engine != "Xray" && _state.FullTunnel;
        var verified = !needsProbe || _connectivityProfileId == _state.ProfileId && _connectivity?.Success == true;
        var earlyVerified = _state.Phase == "connecting" && _state.Engine != "Xray" && _state.FullTunnel &&
            _connectivityProfileId == _state.ProfileId && _connectivity is { Success: true } earlyResult &&
            DateTime.UtcNow - earlyResult.CheckedAt < TimeSpan.FromSeconds(6);
        var connected = _serviceReady && (_state.Phase == "connected" && verified || earlyVerified);
        if (!_serviceReady && HasTunnel)
        { StateTitle.Text = "Служба недоступна"; StateSubtitle.Text = "Не удалось проверить VPN. Перезапустите службу HateVPNBroker."; }
        else
        {
            (StateTitle.Text, StateSubtitle.Text) = _state.Phase switch
            {
                "connected" => ("Подключено", _state.FullTunnel ? "Соединение с вашим сервером установлено." : "Через VPN идут только маршруты профиля."),
                "connecting" => ("Ждём сервер", "Туннель запускается. Проверяем ответ сервера…"),
                "reconnecting" when _state.Engine == "Xray" => ("Нет ответа сервера", "Локальный прокси запущен, но запрос через сервер не проходит. Проверьте подключение и профиль."),
                "reconnecting" => ("Нет ответа сервера", "Проверьте доступность сервера и подключение к интернету."),
                "partial" => ("Туннель не работает", "Сервер отвечает через прокси, но трафик Windows не проходит через VPN. Проверьте маршруты и DNS."),
                "no-data" => ("Нет входящего трафика", "Сервер отвечает на подключение, но сайты не загружаются. Проверьте маршрут к серверу."),
                "error" => ("Ошибка подключения", "Не удалось запустить туннель. Отключите его и проверьте профиль."),
                "other" => ("VPN занят", "Подключение используется другим пользователем Windows."),
                _ => ("Не подключено", Selected is null ? "Добавьте подписку или настройте свой VPS." : !_serviceReady ? "Для подключения установите HateVPN." : "Всё готово. Можно подключаться.")
            };
            if (needsProbe && !verified)
            {
                StateTitle.Text = _connectivityProfileId == _state.ProfileId && _connectivity is { Success: false } failureState
                    ? failureState.Detail.StartsWith("Сайт открылся вне", StringComparison.Ordinal) ? "Интернет вне VPN" : "Сайты не открываются"
                    : "Проверяем интернет…";
                StateSubtitle.Text = _connectivityProfileId == _state.ProfileId && _connectivity is { Success: false } failure
                    ? failure.Detail : "Туннель отвечает. Проверяем загрузку сайта через VPN.";
            }
            else if (earlyVerified) (StateTitle.Text, StateSubtitle.Text) = ("Подключено", "Сайт открылся через VPN. Соединение работает.");
            else if (connected && needsProbe) StateSubtitle.Text = "Сайт открылся через VPN. Соединение работает.";
        }
        var activeProfile = _profiles.Profiles.FirstOrDefault(p => p.Id == _state.ProfileId);
        var switchReady = HasTunnel && Selected is not null && Selected.Id != _state.ProfileId;
        if (switchReady && _connectionAction is null)
            StateSubtitle.Text = $"Сейчас: {PublicLabel(activeProfile?.Name ?? "сервер")}. Выбран: {PublicLabel(Selected!.Name)}.";
        if (_connectionAction is not null)
        {
            StateTitle.Text = _connectionAction == "disconnect" ? "Отключаемся…" : _connectionAction == "switch" ? "Меняем сервер…" : "Подключаемся…";
            StateSubtitle.Text = _connectionAction == "disconnect" ? "Завершаем соединение с сервером." : _connectionAction == "switch" ? "Отключаем предыдущий сервер и запускаем выбранный." : "Проверяем профиль и запускаем соединение.";
        }
        StatusEyebrow.Text = connected ? (_state.FullTunnel ? "СОЕДИНЕНИЕ УСТАНОВЛЕНО" : "ЧАСТИЧНЫЙ ТУННЕЛЬ") :
            needsProbe && _connectivity is { Success: false } ? "ПРОВЕРКА СВЯЗИ НЕ ПРОШЛА" : "ВАШ ЛИЧНЫЙ VPN";
        StatusDot.Fill = new SolidColorBrush(connected ? Color.FromRgb(176, 207, 182) : Color.FromRgb(179, 189, 197));
        ConnectLabel.Text = _connectionAction == "disconnect" ? "Отключаем…" : _connectionAction == "switch" ? "Переключаем…" : _connectionAction == "connect" ? "Подключаем…" : switchReady ? "Переключиться" : HasTunnel ? "Отключить" : Selected is null ? "Добавить подключение" : "Подключиться";
        System.Windows.Automation.AutomationProperties.SetName(ConnectButton, ConnectLabel.Text);
        ConnectButton.IsEnabled = !_busy && _state.Owned;
        DisconnectCurrentButton.Visibility = switchReady && _connectionAction is null ? Visibility.Visible : Visibility.Collapsed;
        DisconnectCurrentButton.IsEnabled = !_busy && _serviceReady;
        HomeProgress.Visibility = _connectionAction is not null || needsProbe && !verified && _connectivity is null || !connected && _state.Phase is ("connecting" or "reconnecting" or "partial" or "no-data") ? Visibility.Visible : Visibility.Collapsed;
        FooterText.Text = !_serviceReady ? "Для подключения установите HateVPN" : connected ?
            _state.Engine == "Xray" ? "Соединение защищено" : $"↓ {Bytes(_state.Received)}     ↑ {Bytes(_state.Sent)}" :
            HasTunnel ? "Откройте настройки для проверки и отчёта" : "Подписка или собственный сервер";
        ServiceStatusText.Text = _serviceReady ? "Служба VPN работает. Профили зашифрованы средствами Windows." : "Служба недоступна. Запустите установщик HateVPN или проверьте HateVPNBroker в службах Windows.";
        ConnectivityStatusText.Text = _state.Phase == "off" ? "Проверка связи доступна после подключения." :
            _state.Engine == "Xray" ? "Подписка проверяется службой VPN автоматически." :
            _connectivity?.Detail ?? "Ожидаем проверку загрузки сайта.";
        if (_tray is not null) _tray.Text = "HateVPN · " + StateTitle.Text;
        if (_trayConnect is not null) { _trayConnect.Text = ConnectLabel.Text; _trayConnect.Enabled = !_busy && _state.Owned; }
        var selected = Selected ?? activeProfile;
        ProfileName.Text = PublicLabel(selected?.Name ?? "Добавить подключение");
        ProfileCaption.Text = selected is null ? "Подписка или свой VPS" : selected.IsInvitation
            ? (switchReady ? "Выбран для переключения · " : "Личный доступ · ") + selected.Name
            : (switchReady ? "Выбран для переключения · " : selected.SubscriptionUrl is null ? "Свой сервер · " : "Подписка · ") + selected.Endpoint;
        UpdateInteraction();
    }

    private async Task CheckConnectivityAsync()
    {
        if (_checkingConnectivity || _preview || _state.ProfileId is null) return;
        var profile = _profiles.Profiles.FirstOrDefault(p => p.Id == _state.ProfileId);
        if (profile is null) return;
        var profileId = profile.Id;
        var phaseAtStart = _state.Phase;
        var session = _connectivitySession;
        using var cancellation = new CancellationTokenSource();
        _connectivityCancellation = cancellation;
        _checkingConnectivity = true;
        if (_connectivityProfileId != profileId) _connectivity = null;
        _connectivityProfileId = profileId;
        UpdateState();
        try
        {
            var result = await ConnectivityProbe.CheckAsync(profile.Config, cancellation.Token);
            if (session == _connectivitySession && _state.ProfileId == profileId && _state.Phase is ("connecting" or "reconnecting" or "connected" or "no-data") &&
                (result.Success || phaseAtStart is ("connected" or "no-data")))
            {
                _connectivity = result;
                if (result.Success && _connectStartedAt != 0 && _siteReadyTime is null)
                    _siteReadyTime = Stopwatch.GetElapsedTime(_connectStartedAt);
            }
        }
        catch
        {
            if (session == _connectivitySession && _state.ProfileId == profileId && phaseAtStart is ("connected" or "no-data"))
                _connectivity = new(false, "Проверка сайта не завершилась.", DateTime.UtcNow);
        }
        finally
        {
            if (ReferenceEquals(_connectivityCancellation, cancellation)) _connectivityCancellation = null;
            _checkingConnectivity = false; UpdateState();
        }
    }

    private void ResetConnectivity()
    {
        _connectivitySession++;
        _connectivityCancellation?.Cancel();
        _connectivity = null;
        _connectivityProfileId = null;
    }

    private static string Bytes(ulong bytes) => bytes >= 1073741824 ? $"{bytes / 1073741824d:F1} ГБ" : bytes >= 1048576 ? $"{bytes / 1048576d:F1} МБ" : $"{bytes / 1024d:F0} КБ";


    private static string PublicLabel(string text) => text
        .Replace("XRay REALITY", "VPN", StringComparison.OrdinalIgnoreCase)
        .Replace("AmneziaWG", "VPN", StringComparison.OrdinalIgnoreCase)
        .Replace("Amnezia WG", "VPN", StringComparison.OrdinalIgnoreCase);

    private void Import_Click(object sender, RoutedEventArgs e) => OpenProfiles();
    private void OpenProfiles()
    {
        if (!_storageOk) { ShowError("Хранилище профилей недоступно. Существующий файл не будет перезаписан."); return; }
        if (_busy) return;
        RefreshProfiles(); LinkMessage.Visibility = Visibility.Collapsed; ProfileSheet.Visibility = Visibility.Visible;
    }

    private void RefreshProfiles()
    {
        var entries = ConnectionCatalog.Entries(_profiles)
            .Select(entry => entry with { Name = PublicLabel(entry.Name), Description = PublicLabel(entry.Description) })
            .ToList();
        ProfilesList.ItemsSource = entries;
        ProfilesList.Visibility = entries.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        EmptyProfiles.Visibility = entries.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        DeleteProfileButton.IsEnabled = Selected is not null;
        ProfileCountText.Text = entries.Count == 0 ? "" : entries.Count.ToString();
        UpdateState();
    }

    private void ConnectionCard_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || sender is not Button { Tag: ConnectionEntry entry }) return;
        if (entry.SubscriptionUrl is not null)
        {
            _subscriptionReturnButton = sender as Button;
            _subscriptionUrlOpen = entry.SubscriptionUrl;
            RefreshSubscriptionNodes();
            SubscriptionStatusText.Visibility = Visibility.Collapsed;
            ProfileSheet.Visibility = Visibility.Collapsed;
            SubscriptionSheet.Visibility = Visibility.Visible;
            return;
        }
        SelectProfile(entry.ProfileId);
    }

    private void RefreshSubscriptionNodes()
    {
        if (_subscriptionUrlOpen is null) return;
        var members = _profiles.Profiles.Where(p => p.SubscriptionUrl == _subscriptionUrlOpen).ToList();
        CurrentSubscriptionTitle.Text = Uri.TryCreate(_subscriptionUrlOpen, UriKind.Absolute, out var uri) ? uri.Host : "Подписка";
        SubscriptionNodeCount.Text = $"{members.Count} {ConnectionCatalog.ServerWord(members.Count)}";
        SubscriptionNodes.ItemsSource = members.Select(p => new ConnectionEntry(p.Id, PublicLabel(p.Name),
            (p.Id == _state.ProfileId && HasTunnel ? "Подключён · " : p.Id == _profiles.SelectedId ? "Выбран · " : "") + p.Endpoint,
            _subscriptionUrlOpen, p.Id, p.Id == _profiles.SelectedId)).ToList();
    }

    private void SubscriptionNode_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || sender is not Button { Tag: ConnectionEntry entry }) return;
        SelectProfile(entry.ProfileId);
    }

    private void SelectProfile(string profileId)
    {
        if (!_profiles.Profiles.Any(p => p.Id == profileId)) return;
        try
        {
            var next = new ProfileData { Profiles = _profiles.Profiles, SelectedId = profileId };
            _store.Save(next); _profiles = next;
            SubscriptionSheet.Visibility = Visibility.Collapsed;
            ProfileSheet.Visibility = Visibility.Collapsed;
            _subscriptionUrlOpen = null;
            _subscriptionReturnButton = null;
            RefreshProfiles();
            ProfileButton.Focus();
        }
        catch { ShowError("Не удалось сохранить выбранный сервер."); }
    }

    private async void AddProfile_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        var picker = new OpenFileDialog { Title = "Добавить сервер", Filter = "Файл настроек VPN (*.conf)|*.conf", CheckFileExists = true };
        if (picker.ShowDialog(this) != true) return;
        _busy = true; UpdateInteraction();
        try
        {
            if (new FileInfo(picker.FileName).Length > 32768) throw new FormatException("Файл конфигурации слишком большой.");
            var file = await File.ReadAllTextAsync(picker.FileName);
            (string Text, string Endpoint, bool FullTunnel) config;
            if (AmneziaWgConfig.IsAmnezia(file))
            {
                var awg = AmneziaWgConfig.Parse(file);
                config = (awg.Text, awg.Endpoint, awg.FullTunnel);
            }
            else
            {
                var wg = WireGuardConfig.Parse(file);
                config = (wg.Text, wg.Endpoint, wg.FullTunnel);
            }
            var name = new string(Path.GetFileNameWithoutExtension(picker.FileName).Where(c => !char.IsControl(c)).Take(48).ToArray());
            var existing = _profiles.Profiles.FirstOrDefault(p => p.Config == config.Text);
            var profile = existing ?? new Profile(Guid.NewGuid().ToString("D"), string.IsNullOrWhiteSpace(name) ? "Мой сервер" : name, config.Text, config.Endpoint, config.FullTunnel);
            var next = new ProfileData { Profiles = [.._profiles.Profiles], SelectedId = profile.Id };
            if (existing is null) next.Profiles.Add(profile);
            _store.Save(next); _profiles = next;
            RefreshProfiles(); ProfileSheet.Visibility = Visibility.Collapsed; ErrorBanner.Visibility = Visibility.Collapsed;
        }
        catch (FormatException ex) { ProfileSheet.Visibility = Visibility.Collapsed; ShowError(ex.Message); }
        catch { ProfileSheet.Visibility = Visibility.Collapsed; ShowError("Не удалось импортировать и сохранить профиль. Проверьте файл и доступ к папке пользователя."); }
        finally { _busy = false; UpdateInteraction(); }
    }

    private async void AddLink_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        var url = LinkBox.Text.Trim();
        LinkMessage.Visibility = Visibility.Collapsed;
        ConnectionLinkKind kind;
        try { kind = ConnectionLink.Detect(url); }
        catch (FormatException ex) { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; return; }
        if (kind == ConnectionLinkKind.OneTimeInvitation)
        {
            if (!_storageOk) { LinkMessage.Text = "Хранилище профилей недоступно. Исправьте его перед активацией одноразовой ссылки."; LinkMessage.Visibility = Visibility.Visible; return; }
            OneTimeInvitation invite;
            try { invite = OneTimeInvitationLink.Parse(url); }
            catch (FormatException ex) { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; return; }
            _busy = true; AddLinkButton.IsEnabled = false; AddLinkButton.Content = "Активируем…";
            UpdateInteraction();
            try
            {
                var claimed = await OneTimeInvitationClient.RedeemAsync(invite);
                var profile = new Profile(Guid.NewGuid().ToString("D"), "Доступ · " + claimed.Name, claimed.Config.Text,
                    claimed.Config.Endpoint, claimed.Config.FullTunnel, IsInvitation: true, InvitationId: claimed.Id);
                var next = new ProfileData
                {
                    Profiles = _profiles.Profiles.Where(p => !p.IsInvitation || p.InvitationId != claimed.Id).Append(profile).ToList(),
                    SelectedId = profile.Id
                };
                _store.Save(next); _profiles = next;
                LinkBox.Clear(); RefreshProfiles(); ProfileSheet.Visibility = Visibility.Collapsed;
                ErrorBanner.Visibility = Visibility.Collapsed;
            }
            catch (Exception ex) when (ex is FormatException or IOException or System.Security.Cryptography.CryptographicException)
            { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; }
            catch { LinkMessage.Text = "Не удалось активировать приглашение. Попросите владельца создать новую ссылку."; LinkMessage.Visibility = Visibility.Visible; }
            finally { _busy = false; AddLinkButton.IsEnabled = true; AddLinkButton.Content = "Добавить"; UpdateInteraction(); }
            return;
        }
        if (kind == ConnectionLinkKind.Invitation)
        {
            try
            {
                var invite = InvitationLink.Parse(url);
                var existing = _profiles.Profiles.FirstOrDefault(p => p.IsInvitation && p.InvitationId == invite.Id);
                var profile = new Profile(existing?.Id ?? Guid.NewGuid().ToString("D"), "Доступ · " + invite.Name, invite.Config.Text,
                    invite.Config.Endpoint, invite.Config.FullTunnel, IsInvitation: true, InvitationId: invite.Id);
                var next = new ProfileData
                {
                    Profiles = _profiles.Profiles.Where(p => p.Id != profile.Id).Append(profile).ToList(),
                    SelectedId = profile.Id
                };
                _store.Save(next); _profiles = next;
                LinkBox.Clear(); RefreshProfiles(); ProfileSheet.Visibility = Visibility.Collapsed;
            }
            catch (FormatException ex) { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; }
            catch { LinkMessage.Text = "Не удалось сохранить приглашение."; LinkMessage.Visibility = Visibility.Visible; }
            return;
        }
        _busy = true; AddLinkButton.IsEnabled = false; AddLinkButton.Content = "Загружаем…";
        UpdateInteraction();
        try
        {
            var nodes = await SubscriptionClient.FetchAsync(url, DeviceIdentity.GetOrCreate());
            var next = ConnectionCatalog.MergeSubscription(_profiles, url, nodes, selectSubscription: true);
            _store.Save(next); _profiles = next;
            LinkBox.Clear(); RefreshProfiles(); ProfileSheet.Visibility = Visibility.Collapsed;
            ErrorBanner.Visibility = Visibility.Collapsed;
        }
        catch (FormatException ex) { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; }
        catch { LinkMessage.Text = "Не удалось загрузить подписку. Проверьте ссылку, сеть и лимит устройств у провайдера."; LinkMessage.Visibility = Visibility.Visible; }
        finally { _busy = false; AddLinkButton.IsEnabled = true; AddLinkButton.Content = "Добавить"; UpdateInteraction(); }
    }

    private void LinkPaste_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        try
        {
            var value = System.Windows.Clipboard.GetText().Trim();
            ConnectionLink.Detect(value);
            LinkBox.Text = value;
            LinkMessage.Visibility = Visibility.Collapsed;
            AddLinkButton.Focus();
        }
        catch (FormatException ex) { LinkMessage.Text = ex.Message; LinkMessage.Visibility = Visibility.Visible; }
        catch { LinkMessage.Text = "Не удалось прочитать буфер обмена. Вставьте ссылку клавишами Ctrl+V."; LinkMessage.Visibility = Visibility.Visible; }
    }

    private void Link_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter || _busy) return;
        e.Handled = true;
        AddLink_Click(sender, new RoutedEventArgs());
    }

    private void OpenVps_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        ProfileSheet.Visibility = Visibility.Collapsed;
        SetVpsStatus("");
        VpsSheet.Visibility = Visibility.Visible;
    }

    private void BackToProfiles_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        InviteSheet.Visibility = Visibility.Collapsed;
        VpsSheet.Visibility = Visibility.Collapsed;
        ProfileSheet.Visibility = Visibility.Visible;
    }

    private void OpenInvites_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        InviteEndpointBox.Text = VpsEndpointBox.Text;
        InviteUserBox.Text = VpsUserBox.Text;
        _inviteUseKey = _vpsUseKey;
        InvitePasswordBox.Password = _vpsUseKey ? "" : VpsPasswordBox.Password;
        InviteKeyBox.Text = _vpsUseKey ? VpsKeyBox.Text : "";
        InvitePasswordCard.Visibility = _inviteUseKey ? Visibility.Collapsed : Visibility.Visible;
        InviteKeyBox.Visibility = _inviteUseKey ? Visibility.Visible : Visibility.Collapsed;
        SetInviteStatus("");
        VpsSheet.Visibility = Visibility.Collapsed;
        InviteSheet.Visibility = Visibility.Visible;
    }

    private void BackToVps_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        InviteSheet.Visibility = Visibility.Collapsed;
        InvitePasswordBox.Clear(); InviteKeyBox.Clear();
        VpsSheet.Visibility = Visibility.Visible;
    }

    private void CloseSubscription_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SubscriptionSheet.Visibility = Visibility.Collapsed;
        ProfileSheet.Visibility = Visibility.Visible;
        _subscriptionUrlOpen = null;
        Dispatcher.BeginInvoke(() =>
        {
            if (_subscriptionReturnButton?.IsVisible == true) _subscriptionReturnButton.Focus();
        }, DispatcherPriority.Input);
    }

    private void VpsHome_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        VpsSheet.Visibility = Visibility.Collapsed;
    }
    private void ImportExistingAwg_Click(object sender, RoutedEventArgs e)
    {
        VpsSheet.Visibility = Visibility.Collapsed;
        ProfileSheet.Visibility = Visibility.Visible;
        AddProfile_Click(sender, e);
    }

    private void VpsSettings_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        OpenSettings();
    }

    private void VpsEndpoint_Changed(object sender, TextChangedEventArgs e)
    {
        if (VpsEndpointHint is not null) VpsEndpointHint.Visibility = string.IsNullOrEmpty(VpsEndpointBox.Text) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SetVpsStatus(string message, bool error = false)
    {
        if (VpsStatusCard is null || VpsProgressText is null) return;
        VpsProgressText.Text = PublicLabel(message);
        VpsStatusCard.Visibility = string.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
        VpsStatusCard.BorderBrush = new SolidColorBrush(error ? Color.FromRgb(193, 112, 112) : Color.FromRgb(119, 131, 139));
        if (error) VpsStatusCard.BringIntoView();
    }

    private void VpsSecret_Pasting(object sender, DataObjectPastingEventArgs e)
    {
        var pasted = e.DataObject.GetData(DataFormats.UnicodeText) as string ?? e.DataObject.GetData(DataFormats.Text) as string;
        if (pasted is null || !pasted.TrimStart().StartsWith("-----BEGIN ", StringComparison.Ordinal) || !pasted.Contains("PRIVATE KEY-----", StringComparison.Ordinal)) return;
        e.CancelCommand();
        _vpsUseKey = true;
        VpsPasswordBox.Clear();
        VpsPasswordBox.Visibility = Visibility.Collapsed;
        VpsKeyBox.Visibility = Visibility.Visible;
        VpsKeyBox.Text = pasted.Trim();
        VpsKeyBox.Focus();
    }

    private void VpsKey_Changed(object sender, TextChangedEventArgs e)
    {
        if (!_vpsUseKey || _busy || !string.IsNullOrEmpty(VpsKeyBox.Text)) return;
        _vpsUseKey = false;
        VpsKeyBox.Visibility = Visibility.Collapsed;
        VpsPasswordBox.Visibility = Visibility.Visible;
        VpsPasswordBox.Focus();
    }

    private void InviteSecret_Pasting(object sender, DataObjectPastingEventArgs e)
    {
        var pasted = e.DataObject.GetData(DataFormats.UnicodeText) as string ?? e.DataObject.GetData(DataFormats.Text) as string;
        if (pasted is null || !pasted.TrimStart().StartsWith("-----BEGIN ", StringComparison.Ordinal) || !pasted.Contains("PRIVATE KEY-----", StringComparison.Ordinal)) return;
        e.CancelCommand();
        _inviteUseKey = true;
        InvitePasswordBox.Clear(); InvitePasswordCard.Visibility = Visibility.Collapsed;
        InviteKeyBox.Visibility = Visibility.Visible; InviteKeyBox.Text = pasted.Trim(); InviteKeyBox.Focus();
    }

    private void InviteKey_Changed(object sender, TextChangedEventArgs e)
    {
        if (!_inviteUseKey || _busy || !string.IsNullOrEmpty(InviteKeyBox.Text)) return;
        _inviteUseKey = false;
        InviteKeyBox.Visibility = Visibility.Collapsed;
        InvitePasswordCard.Visibility = Visibility.Visible;
        InvitePasswordBox.Focus();
    }

    private void SetInviteStatus(string message, bool error = false)
    {
        InviteStatusText.Text = PublicLabel(message);
        InviteStatusCard.Visibility = string.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
        InviteStatusCard.BorderBrush = new SolidColorBrush(error ? Color.FromRgb(193, 112, 112) : Color.FromRgb(119, 131, 139));
        if (!string.IsNullOrEmpty(message)) InviteStatusCard.BringIntoView();
    }

    private VpsCredentials InviteCredentials()
    {
        var endpoint = InviteEndpointBox.Text.Trim().Split(':', 2);
        var port = endpoint.Length == 2 && int.TryParse(endpoint[1], out var parsed) ? parsed : 22;
        if (endpoint.Length == 2 && !int.TryParse(endpoint[1], out _)) throw new FormatException("Укажите правильный SSH-порт.");
        var secret = _inviteUseKey ? InviteKeyBox.Text : InvitePasswordBox.Password;
        return new VpsCredentials(endpoint[0], port, InviteUserBox.Text.Trim(), secret,
            _inviteUseKey || secret.TrimStart().StartsWith("-----BEGIN ", StringComparison.Ordinal));
    }

    private bool TrustInviteHost(VpsCredentials credentials, string fingerprint) =>
        Dispatcher.Invoke(() => MessageBox.Show(this,
            $"SSH-ключ сервера {credentials.Host}:\n{fingerprint}\n\nСверьте отпечаток с данными VPS. Продолжить?",
            "Проверка сервера", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes);

    private async void CreateInvite_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        VpsCredentials credentials;
        try { credentials = InviteCredentials(); }
        catch (FormatException ex) { SetInviteStatus(ex.Message, true); return; }
        var name = InviteNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name)) { SetInviteStatus("Введите имя друга.", true); return; }
        _busy = true; UpdateInteraction(); SetInviteStatus("Создаём личный доступ…");
        try
        {
            var link = await Task.Run(() => VpsInviteManager.Create(credentials, name,
                fingerprint => TrustInviteHost(credentials, fingerprint), message => Dispatcher.Invoke(() => SetInviteStatus(message))));
            CreatedInviteBox.Text = link;
            CreatedInviteBox.Visibility = Visibility.Visible;
            CopyInviteButton.Visibility = Visibility.Visible;
            InviteNameBox.Clear();
            SetInviteStatus("Одноразовая ссылка готова. Её сможет активировать только первый получатель. Скопируйте и передайте другу лично.");
            var current = (InviteList.ItemsSource as IEnumerable<ServerInvite>)?.ToList() ?? [];
            var created = OneTimeInvitationLink.Parse(link);
            current.Add(new ServerInvite(created.Id, created.Name));
            InviteList.ItemsSource = current;
        }
        catch (Exception ex) { SetInviteStatus("Не удалось создать приглашение: " + ex.Message, true); }
        finally { _busy = false; UpdateInteraction(); }
    }

    private void CopyInvite_Click(object sender, RoutedEventArgs e)
    {
        try { if (!string.IsNullOrEmpty(CreatedInviteBox.Text)) Clipboard.SetText(CreatedInviteBox.Text); }
        catch { SetInviteStatus("Не удалось скопировать ссылку. Выделите её и нажмите Ctrl+C.", true); }
    }

    private async void RefreshInvites_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        VpsCredentials credentials;
        try { credentials = InviteCredentials(); }
        catch (FormatException ex) { SetInviteStatus(ex.Message, true); return; }
        _busy = true; UpdateInteraction(); SetInviteStatus("Читаем список приглашений…");
        try
        {
            var invites = await Task.Run(() => VpsInviteManager.List(credentials,
                fingerprint => TrustInviteHost(credentials, fingerprint), message => Dispatcher.Invoke(() => SetInviteStatus(message))));
            InviteList.ItemsSource = invites;
            SetInviteStatus(invites.Count == 0 ? "Активных приглашений нет." : $"Активных приглашений: {invites.Count}.");
        }
        catch (Exception ex) { SetInviteStatus("Не удалось получить приглашения: " + ex.Message, true); }
        finally { _busy = false; UpdateInteraction(); }
    }

    private async void RevokeInvite_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || sender is not Button { Tag: ServerInvite invite }) return;
        if (MessageBox.Show(this, $"Отозвать доступ для «{invite.Name}»? Его подключение перестанет работать.",
            "Отзыв приглашения", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        VpsCredentials credentials;
        try { credentials = InviteCredentials(); }
        catch (FormatException ex) { SetInviteStatus(ex.Message, true); return; }
        _busy = true; UpdateInteraction(); SetInviteStatus("Отзываем доступ…");
        try
        {
            await Task.Run(() => VpsInviteManager.Revoke(credentials, invite.Id,
                fingerprint => TrustInviteHost(credentials, fingerprint), message => Dispatcher.Invoke(() => SetInviteStatus(message))));
            InviteList.ItemsSource = (InviteList.ItemsSource as IEnumerable<ServerInvite>)?
                .Where(item => item.Id != invite.Id).ToList() ?? [];
            SetInviteStatus($"Доступ для «{invite.Name}» отозван. Сервер подтвердил удаление активного клиента.");
        }
        catch (Exception ex) { SetInviteStatus("Не удалось отозвать доступ: " + ex.Message, true); }
        finally { _busy = false; UpdateInteraction(); }
    }

    private async void InstallVps_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (HasTunnel) { SetVpsStatus("Сначала отключите текущее подключение, затем настройте новый сервер.", true); return; }
        var endpoint = VpsEndpointBox.Text.Trim();
        var parts = endpoint.Split(':', 2);
        if (parts[0].Length == 0) { SetVpsStatus("Укажите IP-адрес или домен VPS.", true); return; }
        var port = 22;
        if (parts.Length == 2 && (!int.TryParse(parts[1], out port) || port is < 1 or > 65535))
        { SetVpsStatus("Введите адрес в формате IP:порт, например 255.255.255.255:22.", true); return; }
        var secret = _vpsUseKey ? VpsKeyBox.Text : VpsPasswordBox.Password;
        var isPrivateKey = _vpsUseKey || secret.TrimStart().StartsWith("-----BEGIN ", StringComparison.Ordinal) && secret.Contains("PRIVATE KEY-----", StringComparison.Ordinal);
        var credentials = new VpsCredentials(parts[0], port, VpsUserBox.Text.Trim(), secret, isPrivateKey);
        _busy = true;
        UpdateInteraction();
        InstallVpsButton.IsEnabled = false;
        InstallVpsButton.Content = "Настраиваем сервер…";
        SetVpsStatus("Подготовка подключения…");
        var provisioned = false;
        try
        {
            var config = await Task.Run(() => VpsProvisioner.Install(credentials, VpsProtocol.AmneziaWg,
                fingerprint => Dispatcher.Invoke(() => System.Windows.MessageBox.Show(this,
                    $"SSH-ключ сервера {credentials.Host}:\n{fingerprint}\n\nСверьте отпечаток с данными вашего VPS. Продолжить и передать SSH-доступ?",
                    "Проверка сервера", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes),
                message => Dispatcher.Invoke(() => SetVpsStatus(message))));
            var existing = _profiles.Profiles.FirstOrDefault(p => p.Endpoint == config.Endpoint && p.SubscriptionUrl is null && !p.IsInvitation && AmneziaWgConfig.IsAmnezia(p.Config));
            var profile = new Profile(existing?.Id ?? Guid.NewGuid().ToString("D"), "Мой сервер · " + credentials.Host, config.Config, config.Endpoint, config.FullTunnel);
            var next = new ProfileData { Profiles = _profiles.Profiles.Where(p => p.Id != profile.Id).ToList(), SelectedId = profile.Id };
            next.Profiles.Add(profile);
            _store.Save(next); _profiles = next;
            VpsPasswordBox.Clear(); VpsKeyBox.Clear();
            _vpsUseKey = false; VpsKeyBox.Visibility = Visibility.Collapsed; VpsPasswordBox.Visibility = Visibility.Visible;
            VpsSheet.Visibility = Visibility.Collapsed;
            RefreshProfiles();
            SetVpsStatus("");
            provisioned = true;
        }
        catch (FormatException ex) { SetVpsStatus(ex.Message, true); }
        catch (Renci.SshNet.Common.SshAuthenticationException) { SetVpsStatus("SSH не принял логин, пароль или ключ. Проверьте данные доступа к VPS.", true); }
        catch (Exception ex) { SetVpsStatus("Не удалось настроить VPS: " + (ex is System.Net.Sockets.SocketException ? "сервер не отвечает по SSH." : ex.Message), true); }
        finally { _busy = false; InstallVpsButton.IsEnabled = true; InstallVpsButton.Content = "Продолжить"; UpdateInteraction(); }
        if (provisioned) await ToggleAsync();
    }

    private async void RefreshSubscription_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || _subscriptionUrlOpen is null) return;
        var url = _subscriptionUrlOpen;
        _busy = true;
        RefreshSubscriptionButton.Content = "Обновляем…";
        SubscriptionStatusText.Visibility = Visibility.Collapsed;
        UpdateInteraction();
        try
        {
            var nodes = await SubscriptionClient.FetchAsync(url, DeviceIdentity.GetOrCreate());
            var next = ConnectionCatalog.MergeSubscription(_profiles, url, nodes, selectSubscription: false);
            _store.Save(next); _profiles = next;
            RefreshProfiles(); RefreshSubscriptionNodes();
            SubscriptionStatusText.Text = "Список серверов обновлён.";
            SubscriptionStatusText.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            SubscriptionStatusText.Text = ex is FormatException ? ex.Message : "Не удалось обновить подписку. Сохранённые серверы доступны.";
            SubscriptionStatusText.Visibility = Visibility.Visible;
        }
        finally { _busy = false; RefreshSubscriptionButton.Content = "Обновить список"; UpdateInteraction(); }
    }

    private void DeleteProfile_Click(object sender, RoutedEventArgs e)
    {
        if (_busy || Selected is null) return;
        if (Selected.SubscriptionUrl is { } url) { DeleteSubscription(url); return; }
        if (_state.ProfileId == Selected.Id && HasTunnel)
        { ShowError("Сначала отключите этот сервер, затем удалите его."); return; }
        try
        {
            if (MessageBox.Show(this, $"Удалить «{PublicLabel(Selected.Name)}»?", "Удаление подключения", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            var remaining = _profiles.Profiles.Where(p => p.Id != _profiles.SelectedId).ToList();
            var next = new ProfileData { Profiles = remaining, SelectedId = remaining.FirstOrDefault()?.Id };
            _store.Save(next); _profiles = next; RefreshProfiles();
        }
        catch { ProfileSheet.Visibility = Visibility.Collapsed; ShowError("Не удалось удалить профиль из хранилища."); }
    }

    private void DeleteSubscription_Click(object sender, RoutedEventArgs e)
    {
        if (_subscriptionUrlOpen is not null) DeleteSubscription(_subscriptionUrlOpen);
    }

    private void DeleteSubscription(string url)
    {
        if (_busy) return;
        var members = _profiles.Profiles.Where(p => p.SubscriptionUrl == url).ToList();
        if (members.Count == 0) return;
        if (HasTunnel && members.Any(p => p.Id == _state.ProfileId))
        { ShowError("Сначала отключите эту подписку, затем удалите её."); return; }
        if (MessageBox.Show(this, $"Удалить подписку и все её {members.Count} {ConnectionCatalog.ServerWord(members.Count)}?",
                "Удаление подписки", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try
        {
            var remaining = _profiles.Profiles.Where(p => p.SubscriptionUrl != url).ToList();
            var selectedId = members.Any(p => p.Id == _profiles.SelectedId) ? remaining.FirstOrDefault()?.Id : _profiles.SelectedId;
            var next = new ProfileData { Profiles = remaining, SelectedId = selectedId };
            _store.Save(next); _profiles = next;
            _subscriptionUrlOpen = null;
            _subscriptionReturnButton = null;
            SubscriptionSheet.Visibility = Visibility.Collapsed;
            ProfileSheet.Visibility = Visibility.Visible;
            RefreshProfiles();
        }
        catch { ShowError("Не удалось удалить подписку из хранилища."); }
    }

    private void Settings_Click(object sender, RoutedEventArgs e) => OpenSettings();

    private async void CheckNow_Click(object sender, RoutedEventArgs e)
    {
        if (_preview || _state.ProfileId is null || !_serviceReady)
        { ConnectivityStatusText.Text = "Сначала подключитесь к VPN."; return; }
        if (_state.Engine == "Xray")
        { ConnectivityStatusText.Text = "Подписка проверяется службой VPN автоматически. Обновляем статус…"; await PollAsync(); return; }
        if (_state.Phase is not ("connected" or "no-data"))
        { ConnectivityStatusText.Text = "Дождитесь ответа сервера, затем повторите проверку."; return; }
        if (_checkingConnectivity) return;
        _connectivity = null;
        ConnectivityStatusText.Text = "Проверяем загрузку сайта через VPN…";
        await CheckConnectivityAsync();
    }

    private void SaveReport_Click(object sender, RoutedEventArgs e)
    {
        var picker = new SaveFileDialog
        {
            Title = "Сохранить отчёт HateVPN",
            Filter = "Текстовый файл (*.txt)|*.txt",
            FileName = "HateVPN-report-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".txt",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            OverwritePrompt = true
        };
        if (picker.ShowDialog(this) != true) return;
        var profile = _profiles.Profiles.FirstOrDefault(p => p.Id == _state.ProfileId);
        var kind = profile is null ? "нет" : profile.IsInvitation ? "приглашение" : profile.SubscriptionUrl is not null ? "подписка" : "свой сервер";
        var report = new StringBuilder()
            .AppendLine("HateVPN · отчёт о соединении")
            .AppendLine("Время UTC: " + DateTime.UtcNow.ToString("O"))
            .AppendLine("Windows: " + Environment.OSVersion.Version)
            .AppendLine("Служба доступна: " + (_serviceReady ? "да" : "нет"))
            .AppendLine("Состояние туннеля: " + _state.Phase)
            .AppendLine("Тип подключения: " + kind)
            .AppendLine("Полный туннель: " + (_state.FullTunnel ? "да" : "нет"))
            .AppendLine("Принято байт: " + _state.Received)
            .AppendLine("Отправлено байт: " + _state.Sent)
            .AppendLine("Последний ответ сервера, секунд назад: " +
                (_state.Handshake is { } handshake ? Math.Max(0, (int)(DateTime.UtcNow - handshake).TotalSeconds).ToString() : "нет данных"))
            .AppendLine("Проверка сайта: " + (_connectivity is null ? "не завершена" : _connectivity.Success ? "успешна" : "неуспешна"))
            .AppendLine("Результат: " + (_connectivity?.Detail ?? "нет данных"))
            .AppendLine("Запуск туннеля, мс: " + (_tunnelStartTime?.TotalMilliseconds.ToString("F0") ?? "нет данных"))
            .AppendLine("До открытия сайта, мс: " + (_siteReadyTime?.TotalMilliseconds.ToString("F0") ?? "нет данных"))
            .AppendLine("Адреса серверов, ссылки, пароли и ключи в отчёт не включены.")
            .ToString();
        try { File.WriteAllText(picker.FileName, report, new UTF8Encoding(false)); }
        catch { SettingsSheet.Visibility = Visibility.Collapsed; ShowError("Не удалось сохранить отчёт. Выберите другую папку."); }
    }

    private void OpenSettings()
    {
        if (_busy) return;
        _bindingSettings = true;
        AutostartToggle.IsChecked = UserSettings.AutostartEnabled; TrayToggle.IsChecked = _settings.CloseToTray;
        _bindingSettings = false; SettingsSheet.Visibility = Visibility.Visible;
    }
    private void Autostart_Click(object sender, RoutedEventArgs e)
    {
        if (_bindingSettings) return;
        try { UserSettings.AutostartEnabled = AutostartToggle.IsChecked == true; }
        catch { _bindingSettings = true; AutostartToggle.IsChecked = UserSettings.AutostartEnabled; _bindingSettings = false; SettingsSheet.Visibility = Visibility.Collapsed; ShowError("Не удалось изменить автозапуск Windows."); }
    }
    private void TraySetting_Click(object sender, RoutedEventArgs e)
    {
        if (_bindingSettings) return;
        var old = _settings.CloseToTray;
        try { _settings.CloseToTray = TrayToggle.IsChecked == true; _settings.Save(); }
        catch { _settings.CloseToTray = old; _bindingSettings = true; TrayToggle.IsChecked = old; _bindingSettings = false; SettingsSheet.Visibility = Visibility.Collapsed; ShowError("Не удалось сохранить настройки."); }
    }
    private void Link_Changed(object sender, TextChangedEventArgs e)
    {
        if (LinkHint is not null) LinkHint.Visibility = string.IsNullOrEmpty(LinkBox.Text) ? Visibility.Visible : Visibility.Collapsed;
    }
    private void UpdateInteraction()
    {
        if (SettingsSheet is null || VpsSheet is null || InviteSheet is null || ProfileSheet is null || SubscriptionSheet is null || HomeSurface is null) return;
        var settingsOpen = SettingsSheet.Visibility == Visibility.Visible;
        HomeSurface.IsEnabled = !settingsOpen && VpsSheet.Visibility != Visibility.Visible && InviteSheet.Visibility != Visibility.Visible && ProfileSheet.Visibility != Visibility.Visible && SubscriptionSheet.Visibility != Visibility.Visible;
        ProfileSheet.IsEnabled = !_busy && !settingsOpen;
        SubscriptionSheet.IsEnabled = !_busy && !settingsOpen;
        VpsSheet.IsEnabled = !_busy && !settingsOpen;
        InviteSheet.IsEnabled = !_busy && !settingsOpen;
    }
    private void PageVisibility_Changed(object sender, DependencyPropertyChangedEventArgs e)
    {
        UpdateInteraction();
        if (_preview || sender is not FrameworkElement page || !(bool)e.NewValue || !IsLoaded) return;
        if (SystemParameters.ClientAreaAnimation)
        {
            var slide = new TranslateTransform();
            page.RenderTransform = slide;
            slide.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(14, 0, TimeSpan.FromMilliseconds(220)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
            page.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180)));
        }
        Dispatcher.BeginInvoke(() =>
        {
            if (!page.IsVisible) return;
            if (page == VpsSheet) VpsEndpointBox.Focus();
            else if (page == InviteSheet) InviteEndpointBox.Focus();
            else if (page == ProfileSheet) LinkBox.Focus();
            else if (page == SubscriptionSheet) RefreshSubscriptionButton.Focus();
            else if (page == SettingsSheet) AutostartToggle.Focus();
        });
    }
    private void CloseSettings_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        SettingsSheet.Visibility = Visibility.Collapsed;
        if (VpsSheet.IsVisible) VpsEndpointBox.Focus();
        else if (InviteSheet.IsVisible) InviteEndpointBox.Focus();
        else if (SubscriptionSheet.IsVisible) RefreshSubscriptionButton.Focus();
        else if (ProfileSheet.IsVisible) LinkBox.Focus();
        else ProfileButton.Focus();
    }
    private void CloseSheet_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        ProfileSheet.Visibility = Visibility.Collapsed; SubscriptionSheet.Visibility = Visibility.Collapsed; VpsSheet.Visibility = Visibility.Collapsed; InviteSheet.Visibility = Visibility.Collapsed; SettingsSheet.Visibility = Visibility.Collapsed;
        _subscriptionUrlOpen = null;
        _subscriptionReturnButton = null;
        ProfileButton.Focus();
    }
    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        if (_busy) { e.Handled = true; return; }
        if (ErrorBanner.IsVisible) ErrorBanner.Visibility = Visibility.Collapsed;
        else if (SettingsSheet.IsVisible) CloseSettings_Click(this, new RoutedEventArgs());
        else if (InviteSheet.IsVisible) BackToVps_Click(this, new RoutedEventArgs());
        else if (VpsSheet.IsVisible) BackToProfiles_Click(this, new RoutedEventArgs());
        else if (SubscriptionSheet.IsVisible) CloseSubscription_Click(this, new RoutedEventArgs());
        else if (ProfileSheet.IsVisible) CloseSheet_Click(this, new RoutedEventArgs());
        else return;
        e.Handled = true;
    }
    private void ShowError(string text) { ErrorText.Text = PublicLabel(text); ErrorBanner.Visibility = Visibility.Visible; }
    private void DismissError_Click(object sender, RoutedEventArgs e) => ErrorBanner.Visibility = Visibility.Collapsed;

    internal void RenderPreview(string path, bool connected, bool profiles = false, bool vps = false, bool settings = false, bool empty = false, bool subscription = false, bool switching = false, bool sampleInput = false, bool invites = false)
    {
        _profiles = empty ? new() : new ProfileData { SelectedId = switching ? "preview2" : "preview", Profiles = [
            new Profile("preview", "Амстердам", "", "203.0.113.42:443", true, "https://sub.example.com/example"),
            new Profile("preview2", "Франкфурт", "", "203.0.113.77:443", true, "https://sub.example.com/example"),
            new Profile("preview3", "Роттердам", "", "203.0.113.78:443", true, "https://sub.example.com/example"),
            new Profile("preview4", "Мой VPS", "", "203.0.113.80:443", true)] };
        _serviceReady = true; _state = new(connected ? "connected" : "off", ProfileId: connected ? "preview" : null, FullTunnel: true, Received: 23488102, Sent: 1572864, Engine: "Xray");
        RefreshProfiles();
        if (sampleInput)
        {
            LinkBox.Text = "https://example.com/subscription";
            InviteNameBox.Text = "Друг";
        }
        ProfileSheet.Visibility = profiles ? Visibility.Visible : Visibility.Collapsed;
        if (subscription)
        {
            _subscriptionUrlOpen = "https://sub.example.com/example";
            RefreshSubscriptionNodes();
            ProfileSheet.Visibility = Visibility.Collapsed;
            SubscriptionSheet.Visibility = Visibility.Visible;
        }
        VpsSheet.Visibility = vps ? Visibility.Visible : Visibility.Collapsed;
        InviteSheet.Visibility = invites ? Visibility.Visible : Visibility.Collapsed;
        if (settings) OpenSettings();
        DesignSurface.BeginAnimation(OpacityProperty, null); DesignSurface.Opacity = 1;
        DesignSurface.Measure(new Size(480, 760)); DesignSurface.Arrange(new Rect(0, 0, 480, 760)); DesignSurface.UpdateLayout();
        if (vps && sampleInput) { InviteNameBox.BringIntoView(); DesignSurface.UpdateLayout(); }
        var bitmap = new RenderTargetBitmap(480, 760, 96, 96, PixelFormats.Pbgra32); bitmap.Render(DesignSurface);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.GetFullPath(path)); encoder.Save(file);
    }
    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ChangedButton == MouseButton.Left && e.Source is not Button) DragMove(); }
    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
