using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace HateVPN.Service;

// Keep the server itself reachable through the physical network when the VPN installs a default route.
internal sealed class EndpointRoute : IDisposable
{
    private readonly string _address;
    private readonly int _interfaceIndex;
    private readonly string _gateway;
    private readonly bool _owned;

    private EndpointRoute(string address, int interfaceIndex, string gateway, bool owned)
    {
        _address = address;
        _interfaceIndex = interfaceIndex;
        _gateway = gateway;
        _owned = owned;
    }

    public static EndpointRoute Pin(string endpoint)
    {
        var colon = endpoint.LastIndexOf(':');
        if (colon < 1 || !IPAddress.TryParse(endpoint[..colon], out var ip) ||
            ip.AddressFamily != AddressFamily.InterNetwork)
            return null;

        var address = ip.ToString();
        var script = $$"""
            $ErrorActionPreference = 'Stop'
            $address = '{{address}}'
            $metrics = @{}
            Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object { $metrics[[int]$_.InterfaceIndex] = [int]$_.InterfaceMetric }
            $underlay = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
                Where-Object { $_.NextHop -ne '0.0.0.0' -and $metrics.ContainsKey([int]$_.InterfaceIndex) } |
                Sort-Object @{ Expression = { [int]$_.RouteMetric + $metrics[[int]$_.InterfaceIndex] } } |
                Select-Object -First 1
            if ($null -eq $underlay) { throw 'No physical default route' }
            $existing = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix ($address + '/32') -ErrorAction SilentlyContinue)
            $matching = $existing | Where-Object {
                $_.InterfaceIndex -eq $underlay.InterfaceIndex -and $_.NextHop -eq $underlay.NextHop
            } | Select-Object -First 1
            if ($null -ne $matching) { $owned = 0 }
            elseif ($existing.Count -gt 0) { throw 'The endpoint already has a different route' }
            else {
                New-NetRoute -DestinationPrefix ($address + '/32') -InterfaceIndex $underlay.InterfaceIndex -NextHop $underlay.NextHop -RouteMetric 1 -PolicyStore ActiveStore | Out-Null
                $owned = 1
            }
            'HATEVPN_ROUTE|{0}|{1}|{2}' -f $owned, $underlay.InterfaceIndex, $underlay.NextHop
            """;
        var output = Run(script, "Не удалось создать маршрут к VPN-серверу через основной интернет-адаптер.");
        var marker = output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .LastOrDefault(line => line.StartsWith("HATEVPN_ROUTE|", StringComparison.Ordinal));
        var fields = marker?.Split('|');
        if (fields?.Length != 4 || !int.TryParse(fields[2], out var index) ||
            !IPAddress.TryParse(fields[3], out var gateway))
            throw new FormatException("Не удалось закрепить маршрут к VPN-серверу. Проверьте основной интернет-адаптер.");
        return new EndpointRoute(address, index, gateway.ToString(), fields[1] == "1");
    }

    public void Dispose()
    {
        if (!_owned) return;
        try
        {
            Run($$"""
                Remove-NetRoute -DestinationPrefix '{{_address}}/32' -InterfaceIndex {{_interfaceIndex}} -NextHop '{{_gateway}}' -Confirm:$false -ErrorAction SilentlyContinue
                """, "Не удалось удалить маршрут к VPN-серверу.");
        }
        catch { /* The route belongs to the active store and is cleared on restart. */ }
    }

    internal static string Run(string script, string errorMessage)
    {
        var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"))
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        info.ArgumentList.Add("-NoProfile");
        info.ArgumentList.Add("-NonInteractive");
        info.ArgumentList.Add("-EncodedCommand");
        info.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes(script)));
        using var process = Process.Start(info) ?? throw new IOException("Не удалось открыть настройки маршрутов Windows.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(10000))
        {
            process.Kill(entireProcessTree: true);
            throw new IOException("Настройка сети заняла слишком много времени.");
        }
        var output = stdout.GetAwaiter().GetResult();
        _ = stderr.GetAwaiter().GetResult();
        if (process.ExitCode != 0)
            throw new FormatException(errorMessage);
        return output;
    }
}
