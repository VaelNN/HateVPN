param(
    [Parameter(Mandatory = $true)][string]$ClientInfoPath,
    [Parameter(Mandatory = $true)][string]$ServerHost,
    [string]$BindAddress = '10.8.1.2'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xray = Join-Path $root 'vendor/xray-26.9.9/bin/xray.exe'
$lines = [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $ClientInfoPath).Path)
if ($lines.Length -lt 4 -or !(Test-Path -LiteralPath $xray)) { throw 'Xray client parameters or binary are missing.' }

$socket = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
try { $port = ([Net.IPEndPoint]$socket.Client.LocalEndPoint).Port } finally { $socket.Dispose() }
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ('HateVPN-Xray-DNS-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$process = $null
try {
    $configPath = Join-Path $temp 'client.json'
    $config = @{
        log = @{ loglevel = 'warning' }
        inbounds = @(@{
            tag = 'dns-test'; listen = '127.0.0.1'; port = $port; protocol = 'dokodemo-door'
            settings = @{ address = '1.1.1.1'; port = 53; network = 'udp' }
        })
        outbounds = @(@{
            tag = 'proxy'; protocol = 'vless'; sendThrough = $BindAddress
            settings = @{ address = $ServerHost; port = 443; id = $lines[0]; encryption = 'none'; flow = 'xtls-rprx-vision' }
            streamSettings = @{
                network = 'raw'; security = 'reality'
                realitySettings = @{ serverName = $lines[3]; fingerprint = 'chrome'; password = $lines[1]; shortId = $lines[2] }
            }
        })
    } | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
    & $xray run -test -config $configPath 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw 'Xray rejected the DNS test configuration.' }
    $process = Start-Process -FilePath $xray -ArgumentList "run -config `"$configPath`"" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $temp 'client.err')
    Start-Sleep -Milliseconds 900
    if ($process.HasExited) { throw 'Xray DNS test process exited.' }

    [byte[]]$query = @(0x12,0x34,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x07) +
        [Text.Encoding]::ASCII.GetBytes('example') + [byte[]]@(0x03) +
        [Text.Encoding]::ASCII.GetBytes('com') + [byte[]]@(0x00,0x00,0x01,0x00,0x01)
    $client = [Net.Sockets.UdpClient]::new()
    try {
        $client.Client.ReceiveTimeout = 8000
        [void]$client.Send($query, $query.Length, '127.0.0.1', $port)
        $endpoint = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
        $answer = $client.Receive([ref]$endpoint)
        if ($answer.Length -lt 12 -or $answer[0] -ne 0x12 -or $answer[1] -ne 0x34 -or
            ($answer[3] -band 0x0f) -ne 0 -or ($answer[6] -eq 0 -and $answer[7] -eq 0)) {
            throw 'DNS response was invalid or empty.'
        }
        Write-Output 'VLESS REALITY UDP DNS through VPS passed.'
    }
    finally { $client.Dispose() }
}
finally {
    if ($null -ne $process) {
        try { if (!$process.HasExited) { $process.Kill(); $process.WaitForExit(3000) | Out-Null } } catch { }
        $process.Dispose()
    }
    $canonical = [IO.Path]::GetFullPath($temp)
    if ($canonical.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($canonical).StartsWith('HateVPN-Xray-DNS-', [StringComparison]::Ordinal)) {
        try { [IO.Directory]::Delete($canonical, $true) } catch { }
    }
}

