param(
    [Parameter(Mandatory = $true)][string]$ClientInfoPath,
    [Parameter(Mandatory = $true)][string]$ServerHost,
    [string]$BindAddress = '10.8.1.2',
    [string]$DestinationIp = '104.20.23.154'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xray = Join-Path $root 'vendor/xray-26.9.9/bin/xray.exe'
$lines = [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $ClientInfoPath).Path)
if ($lines.Length -lt 4 -or !(Test-Path -LiteralPath $xray)) { throw 'Xray client parameters or binary are missing.' }

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
try { $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ('HateVPN-Xray-IP-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$process = $null
try {
    $configPath = Join-Path $temp 'client.json'
    $config = @{
        log = @{ loglevel = 'warning' }
        inbounds = @(@{
            tag = 'ip-test'; listen = '127.0.0.1'; port = $port; protocol = 'dokodemo-door'
            settings = @{ address = $DestinationIp; port = 443; network = 'tcp' }
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
    if ($LASTEXITCODE) { throw 'Xray rejected the IP destination test configuration.' }
    $process = Start-Process -FilePath $xray -ArgumentList "run -config `"$configPath`"" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $temp 'client.err')
    Start-Sleep -Milliseconds 900
    if ($process.HasExited) { throw 'Xray IP destination test process exited.' }
    $result = & curl.exe --silent --output NUL --write-out 'HTTP=%{http_code}; CONNECT=%{time_connect}; TOTAL=%{time_total}' --max-time 15 --noproxy '*' --connect-to "www.example.com:443:127.0.0.1:$port" https://www.example.com/
    Write-Output "IP destination $DestinationIp : $result; CURL_EXIT=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0 -or $result -notmatch 'HTTP=2[0-9][0-9]') { exit 1 }
}
finally {
    if ($null -ne $process) {
        try { if (!$process.HasExited) { $process.Kill(); $process.WaitForExit(3000) | Out-Null } } catch { }
        $process.Dispose()
    }
    $canonical = [IO.Path]::GetFullPath($temp)
    if ($canonical.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($canonical).StartsWith('HateVPN-Xray-IP-', [StringComparison]::Ordinal)) {
        try { [IO.Directory]::Delete($canonical, $true) } catch { }
    }
}

