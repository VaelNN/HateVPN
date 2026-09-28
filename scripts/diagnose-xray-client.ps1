param([string]$ServerHost = '')
$ErrorActionPreference = 'Stop'
$reportPath = Join-Path $PSScriptRoot ('HateVPN-Xray-client-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$report = [Collections.Generic.List[string]]::new()

function Add-Section([string]$name, [scriptblock]$body) {
    $report.Add('')
    $report.Add('=== ' + $name + ' ===')
    try {
        $value = & $body 2>&1 | Out-String -Width 240
        $report.Add($value.TrimEnd())
    }
    catch {
        $report.Add('ERROR: ' + $_.Exception.Message)
    }
}

function Test-Web([string]$name, [string]$url, [bool]$useProxy) {
    Add-Section $name {
        $arguments = @('--silent', '--output', 'NUL', '--write-out', 'HTTP=%{http_code}; REMOTE=%{remote_ip}; CONNECT=%{time_connect}; TOTAL=%{time_total}', '--connect-timeout', '5', '--max-time', '12')
        if ($useProxy) { $arguments += @('--proxy', 'http://127.0.0.1:29452', '--noproxy', 'localhost') }
        else { $arguments += @('--noproxy', '*') }
        $arguments += $url
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $result = & curl.exe @arguments
            $exitCode = $LASTEXITCODE
            $result
            'CURL_EXIT=' + $exitCode
        }
        finally { $ErrorActionPreference = $oldPreference }
    }
}

$report.Add('HateVPN Xray client check')
$report.Add('TIME=' + (Get-Date -Format o))
$report.Add('No VPN connection is started or stopped by this script.')
$report.Add('No profile, password, or private key is read.')

Add-Section 'HateVPN processes and services' {
    'PROCESSES'
    Get-Process HateVPN, xray -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path | Format-Table -AutoSize | Out-String
    'SERVICES'
    Get-Service HateVPNBroker, HateVPNAWG -ErrorAction SilentlyContinue | Select-Object Name, Status | Format-Table -AutoSize | Out-String
}
Add-Section 'Network adapters' {
    Get-NetAdapter | Select-Object Name, Status, ifIndex, InterfaceDescription
}
Add-Section 'Adapter addresses and metrics' {
    'IPV4 ADDRESSES'
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -NotLike '169.254*' |
        Select-Object InterfaceAlias, IPAddress, PrefixLength | Format-Table -AutoSize | Out-String
    'INTERFACE METRICS'
    Get-NetIPInterface | Select-Object InterfaceAlias, AddressFamily, InterfaceMetric, ConnectionState |
        Format-Table -AutoSize | Out-String
}
Add-Section 'Relevant IPv4 routes' {
    Get-NetRoute -AddressFamily IPv4 | Where-Object {
        $_.DestinationPrefix -in @('0.0.0.0/0', ($ServerHost + '/32'), '1.1.1.1/32')
    } | Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric, InterfaceMetric
}
Add-Section 'IPv6 default routes' {
    Get-NetRoute -AddressFamily IPv6 | Where-Object DestinationPrefix -EQ '::/0' |
        Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric, InterfaceMetric
}
Add-Section 'DNS servers' {
    Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceAlias, AddressFamily, ServerAddresses
}
Add-Section 'Windows proxy and Xray listener' {
    $settings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    'PROXY_ENABLED=' + $settings.ProxyEnable
    'HATEVPN_PROXY=' + [bool]($settings.ProxyServer -eq '127.0.0.1:29452')
    'OTHER_PROXY=' + [bool]($settings.ProxyServer -and $settings.ProxyServer -ne '127.0.0.1:29452')
    'PAC_PRESENT=' + [bool]$settings.AutoConfigURL
    Get-NetTCPConnection -LocalPort 29452 -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, OwningProcess
}
Add-Section 'TCP 443 to VPS through the physical adapter' {
    if ([string]::IsNullOrWhiteSpace($ServerHost)) { 'Skipped: pass -ServerHost to check a specific VPS.'; return }
    $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
        Where-Object { $_.NextHop -ne '0.0.0.0' -and $_.InterfaceAlias -notmatch 'Radmin|Tailscale' } |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($null -eq $route) { throw 'Physical default route not found.' }
    $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex |
        Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1 -ExpandProperty IPAddress
    $socket = $null
    try {
        $local = [Net.IPEndPoint]::new([Net.IPAddress]::Parse($address), 0)
        $socket = [Net.Sockets.TcpClient]::new($local)
        $task = $socket.ConnectAsync($ServerHost, 443)
        $finished = $task.Wait(5000)
        'PHYSICAL_SOURCE=' + $address
        'CONNECTED=' + [bool]($finished -and $socket.Connected)
    }
    catch {
        'PHYSICAL_SOURCE=' + $address
        'CONNECTED=False'
        'ERROR=' + $_.Exception.GetBaseException().Message
    }
    finally { if ($null -ne $socket) { $socket.Dispose() } }
}
Add-Section 'DNS resolution of example.com' {
    Resolve-DnsName example.com -Type A -ErrorAction Stop |
        Select-Object Name, Type, IPAddress
}
Test-Web 'Website through Xray proxy' 'https://www.example.com/' $true
Test-Web 'Website without browser proxy' 'https://www.example.com/' $false
Test-Web 'IP-only direct HTTPS' 'https://1.1.1.1/cdn-cgi/trace' $false

[IO.File]::WriteAllLines($reportPath, $report, [Text.UTF8Encoding]::new($true))
Write-Output ('Report saved: ' + $reportPath)

