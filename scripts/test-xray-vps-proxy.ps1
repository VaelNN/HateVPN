param(
    [Parameter(Mandatory = $true)][string]$ClientInfoPath,
    [Parameter(Mandatory = $true)][string]$ServerHost,
    [string]$BindAddress = '10.8.1.2'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xray = Join-Path $root 'vendor/xray-26.9.9/bin/xray.exe'
if (!(Test-Path -LiteralPath $xray)) { throw 'Xray client binary is missing.' }
$lines = [IO.File]::ReadAllLines((Resolve-Path -LiteralPath $ClientInfoPath).Path)
if ($lines.Length -lt 4) { throw 'Xray client parameters are incomplete.' }

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
try { $proxyPort = $listener.LocalEndpoint.Port } finally { $listener.Stop() }
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ('HateVPN-Xray-Remote-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$process = $null
try {
    $configPath = Join-Path $temp 'client.json'
    $config = @{
        log = @{ loglevel = 'warning' }
        inbounds = @(@{ tag = 'local-http'; listen = '127.0.0.1'; port = $proxyPort; protocol = 'http' })
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
    if ($LASTEXITCODE) { throw 'Xray rejected the proxy-only client configuration.' }
    $process = Start-Process -FilePath $xray -ArgumentList "run -config `"$configPath`"" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $temp 'client.err')
    Start-Sleep -Milliseconds 900
    if ($process.HasExited) { throw 'Xray proxy-only client exited before the request.' }
    $status = (& curl.exe --proxy "http://127.0.0.1:$proxyPort" --silent --show-error --output NUL --write-out '%{http_code}' --max-time 20 https://www.example.com/).Trim()
    if ($LASTEXITCODE -or $status -notmatch '^[23][0-9][0-9]$') { throw "Remote Xray proxy request failed (HTTP $status)." }
    Write-Output "Remote VLESS REALITY proxy passed (HTTP $status)."
}
finally {
    if ($null -ne $process) {
        try { if (!$process.HasExited) { $process.Kill(); $process.WaitForExit(3000) | Out-Null } } catch { }
        $process.Dispose()
    }
    $canonical = [IO.Path]::GetFullPath($temp)
    if ($canonical.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($canonical).StartsWith('HateVPN-Xray-Remote-', [StringComparison]::Ordinal)) {
        try { [IO.Directory]::Delete($canonical, $true) } catch { }
    }
}

