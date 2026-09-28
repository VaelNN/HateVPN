param([string]$TestUrl = 'https://www.example.com/')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$xray = Join-Path $root 'vendor/xray-26.9.9/bin/xray.exe'
if (!(Test-Path -LiteralPath $xray)) { throw 'Xray is missing. Run prepare-xray.ps1 first.' }

function New-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}

$serverPort = New-FreePort
do { $proxyPort = New-FreePort } while ($proxyPort -eq $serverPort)
$pair = @(& $xray x25519)
if ($LASTEXITCODE) { throw 'Xray key generation failed.' }
$privateKey = ($pair | Where-Object { $_ -match '^PrivateKey: ' }) -replace '^PrivateKey: ', ''
$publicKey = ($pair | Where-Object { $_ -match '^Password \(PublicKey\): ' }) -replace '^Password \(PublicKey\): ', ''
if (!$privateKey -or !$publicKey) { throw 'Xray key format changed.' }
$clientId = [guid]::NewGuid().ToString()
$shortBytes = New-Object byte[] 8
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $random.GetBytes($shortBytes) } finally { $random.Dispose() }
$shortId = -join ($shortBytes | ForEach-Object { $_.ToString('x2') })
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temp = Join-Path $tempBase ('HateVPN-Xray-Test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
$server = $null
$client = $null

try {
    $serverConfig = Join-Path $temp 'server.json'
    $clientConfig = Join-Path $temp 'client.json'
    $serverJson = @"
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$serverPort,"protocol":"vless","settings":{"clients":[{"id":"$clientId","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"target":"www.microsoft.com:443","xver":0,"serverNames":["www.microsoft.com"],"privateKey":"$privateKey","shortIds":["$shortId"]}}}],"outbounds":[{"tag":"direct","protocol":"freedom"}]}
"@
    $clientJson = @"
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"127.0.0.1","port":$proxyPort,"protocol":"http"}],"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"address":"127.0.0.1","port":$serverPort,"id":"$clientId","encryption":"none","flow":"xtls-rprx-vision"},"streamSettings":{"network":"raw","security":"reality","realitySettings":{"serverName":"www.microsoft.com","fingerprint":"chrome","password":"$publicKey","shortId":"$shortId"}}}]}
"@
    [IO.File]::WriteAllText($serverConfig, $serverJson, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($clientConfig, $clientJson, [Text.UTF8Encoding]::new($false))
    & $xray run -test -config $serverConfig 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw 'Server config rejected by Xray.' }
    & $xray run -test -config $clientConfig 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw 'Client config rejected by Xray.' }
    $server = Start-Process -FilePath $xray -ArgumentList "run -config `"$serverConfig`"" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $temp 'server.err')
    $client = Start-Process -FilePath $xray -ArgumentList "run -config `"$clientConfig`"" -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $temp 'client.err')
    Start-Sleep -Milliseconds 900
    if ($server.HasExited -or $client.HasExited) { throw 'A local Xray process exited before the request.' }
    $status = (& curl.exe --proxy "http://127.0.0.1:$proxyPort" --silent --show-error --output NUL --write-out '%{http_code}' --max-time 20 $TestUrl).Trim()
    if ($LASTEXITCODE -or $status -notmatch '^[23][0-9][0-9]$') { throw "Local REALITY request failed (HTTP $status)." }
    Write-Output "Local VLESS REALITY handshake and HTTP proxy passed (HTTP $status)."
}
finally {
    foreach ($process in @($client, $server)) {
        if ($null -ne $process) {
            try { if (!$process.HasExited) { $process.Kill(); $process.WaitForExit(3000) | Out-Null } } catch { }
            $process.Dispose()
        }
    }
    $canonical = [IO.Path]::GetFullPath($temp)
    if ($canonical.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($canonical).StartsWith('HateVPN-Xray-Test-', [StringComparison]::Ordinal)) {
        try { [IO.Directory]::Delete($canonical, $true) } catch { }
    }
}
