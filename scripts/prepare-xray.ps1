$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root 'vendor/xray-26.9.9'
$archive = Join-Path $directory 'Xray-windows-64.zip'
$destination = Join-Path $directory 'bin'
$expected = '244deaba2098c2964e49bba90df3707777e5f5f428a82d2f29604015f24beec2'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
if (!(Test-Path -LiteralPath $archive)) {
    & curl.exe -fL --retry 2 --silent --show-error 'https://github.com/XTLS/Xray-core/releases/download/v26.9.9/Xray-windows-64.zip' -o $archive
    if ($LASTEXITCODE) { throw 'XRay download failed' }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'XRay archive checksum mismatch'
}
Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
foreach ($name in @('xray.exe', 'wintun.dll', 'LICENSE', 'LICENSE-Wintun')) {
    if (!(Test-Path -LiteralPath (Join-Path $destination $name))) { throw "XRay archive is missing $name" }
}
Write-Output 'XRay 26.9.9 archive verified.'
