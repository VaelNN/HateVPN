#nullable enable
using System.Diagnostics;
using System.Net;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

namespace HateVPN.Service;

internal sealed class XrayRuntime : IDisposable
{
    private readonly Process _process;
    private readonly string _configPath;
    private readonly CancellationTokenSource _stop = new();
    private volatile bool _proxyHealthy;
    private volatile bool _tunnelHealthy;
    public bool IsRunning { get { try { return !_process.HasExited; } catch { return false; } } }
    public bool ProxyHealthy => _proxyHealthy;
    public bool Healthy => _proxyHealthy && _tunnelHealthy;

    public XrayRuntime(string config)
    {
        var baseDir = AppContext.BaseDirectory;
        var executable = Path.Combine(baseDir, "xray.exe");
        var driver = Path.Combine(baseDir, "wintun.dll");
        if (!File.Exists(executable) || !File.Exists(driver))
            throw new FileNotFoundException("Xray или Wintun не установлены. Переустановите HateVPN.");
        var stateDir = Path.Combine(baseDir, "State");
        if (Directory.Exists(stateDir) && (File.GetAttributes(stateDir) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Недопустимый каталог службы.");
        Directory.CreateDirectory(stateDir);
        var acl = new DirectorySecurity(); acl.SetAccessRuleProtection(true, false);
        foreach (var kind in new[] { WellKnownSidType.LocalSystemSid, WellKnownSidType.BuiltinAdministratorsSid })
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(kind, null), FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(stateDir).SetAccessControl(acl);
        _configPath = Path.Combine(stateDir, "xray.json");
        if (File.Exists(_configPath) && (File.GetAttributes(_configPath) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Недопустимый файл службы.");
        File.WriteAllText(_configPath, config, new UTF8Encoding(false));
        var start = new ProcessStartInfo(executable) { WorkingDirectory = baseDir, UseShellExecute = false,
            CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add("run"); start.ArgumentList.Add("-config"); start.ArgumentList.Add(_configPath);
        _process = new Process { StartInfo = start };
        try
        {
            if (!_process.Start()) throw new IOException("Не удалось запустить Xray.");
            _process.BeginOutputReadLine(); _process.BeginErrorReadLine();
        }
        catch
        {
            _process.Dispose();
            File.Delete(_configPath);
            throw;
        }
        _ = Task.Run(CheckHealthAsync);
    }

    private async Task CheckHealthAsync()
    {
        using var proxyHandler = new HttpClientHandler { Proxy = new WebProxy("http://127.0.0.1:29452"), UseProxy = true };
        using var directHandler = new HttpClientHandler { UseProxy = false };
        using var proxyClient = new HttpClient(proxyHandler) { Timeout = TimeSpan.FromSeconds(7) };
        using var directClient = new HttpClient(directHandler) { Timeout = TimeSpan.FromSeconds(7) };
        var targets = new[] { "https://1.1.1.1/cdn-cgi/trace", "https://1.0.0.1/cdn-cgi/trace" };
        while (!_stop.IsCancellationRequested && IsRunning)
        {
            var proxyHealthy = false;
            var tunnelHealthy = false;
            foreach (var target in targets)
            {
                try
                {
                    var proxyIp = TraceIp(await proxyClient.GetStringAsync(target, _stop.Token));
                    if (proxyIp is null) continue;
                    proxyHealthy = true;
                    var directIp = TraceIp(await directClient.GetStringAsync(target, _stop.Token));
                    if (directIp is not null && proxyIp.Equals(directIp, StringComparison.OrdinalIgnoreCase))
                    { tunnelHealthy = true; break; }
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { break; }
                catch { /* Try the other trace endpoint. */ }
            }
            if (tunnelHealthy)
            {
                const string site = "https://www.example.com/";
                try
                {
                    using var viaProxy = await proxyClient.GetAsync(site, HttpCompletionOption.ResponseHeadersRead, _stop.Token);
                    using var viaTunnel = await directClient.GetAsync(site, HttpCompletionOption.ResponseHeadersRead, _stop.Token);
                    tunnelHealthy = viaProxy.IsSuccessStatusCode && viaTunnel.IsSuccessStatusCode;
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { break; }
                catch { tunnelHealthy = false; }
            }
            _proxyHealthy = proxyHealthy;
            _tunnelHealthy = tunnelHealthy;
            try { await Task.Delay(TimeSpan.FromSeconds(Healthy ? 20 : 4), _stop.Token); }
            catch (OperationCanceledException) { break; }
        }
    }

    private static string? TraceIp(string body)
    {
        var line = body.Split('\n').FirstOrDefault(value => value.StartsWith("ip=", StringComparison.Ordinal));
        var value = line?[3..].Trim();
        return IPAddress.TryParse(value, out var address) ? address.ToString() : null;
    }

    public void Dispose()
    {
        _stop.Cancel();
        try { if (!_process.HasExited) { _process.Kill(entireProcessTree: true); _process.WaitForExit(5000); } } catch { }
        _process.Dispose(); _stop.Dispose();
        try { File.Delete(_configPath); } catch { }
    }
}
