using HateVPN.Core;
using System.Net;
using System.Text.RegularExpressions;

namespace HateVPN.Service;

internal static class TunnelDns
{
    public static void Apply(AmneziaWgConfig config)
    {
        var match = Regex.Match(config.Text, @"(?m)^DNS\s*=\s*(.+?)\s*$", RegexOptions.IgnoreCase);
        if (!match.Success) throw new FormatException("В профиле отсутствуют DNS-серверы.");
        var addresses = match.Groups[1].Value.Split(',').Select(value => value.Trim())
            .Select(value => IPAddress.TryParse(value, out var address) ? address : null).ToArray();
        if (addresses.Length == 0 || addresses.Any(address => address is null))
            throw new FormatException("В профиле указаны некорректные DNS-серверы.");
        var servers = string.Join(", ", addresses.Select(address => "'" + address + "'"));
        var script = $$"""
            $ErrorActionPreference = 'Stop'
            $servers = @({{servers}})
            $adapter = $null
            for ($attempt = 0; $attempt -lt 16; $attempt++) {
                $adapter = Get-NetAdapter -Name 'HateVPNAWG' -ErrorAction SilentlyContinue
                if ($null -ne $adapter -and $adapter.Status -eq 'Up') { break }
                Start-Sleep -Milliseconds 250
            }
            if ($null -eq $adapter -or $adapter.Status -ne 'Up') { throw 'VPN adapter unavailable' }
            $current = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | ForEach-Object { $_.ServerAddresses })
            if (@($servers | Where-Object { $_ -notin $current }).Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
                Clear-DnsClientCache
            }
            $configured = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction Stop | ForEach-Object { $_.ServerAddresses })
            if (@($servers | Where-Object { $_ -notin $configured }).Count -gt 0) { throw 'DNS verification failed' }
            'HATEVPN_DNS_OK'
            """;
        var output = EndpointRoute.Run(script, "Не удалось назначить DNS-серверы VPN-адаптеру.");
        if (!output.Contains("HATEVPN_DNS_OK", StringComparison.Ordinal))
            throw new FormatException("Не удалось проверить DNS-серверы VPN-адаптера.");
    }
}
