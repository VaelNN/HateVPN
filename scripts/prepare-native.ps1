$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = Join-Path $projectRoot 'vendor/wireguard-windows'
$revision = '6ece77bc487c8aa697e3c092197621c4f3e5ccb8'
if (!(Test-Path (Join-Path $source '.git'))) { & git clone https://github.com/WireGuard/wireguard-windows.git $source; & git -C $source checkout --detach $revision; if ($LASTEXITCODE) { throw 'WireGuard checkout failed' } }
if ((& git -C $source rev-parse HEAD) -ne $revision) { throw 'Unexpected WireGuard source revision' }
$deps = Join-Path $projectRoot 'vendor/toolchain'
New-Item -ItemType Directory -Path $deps -Force | Out-Null
function Get-VerifiedArchive($name, $url, $hash, $folder) {
    $zip = Join-Path $deps $name
    if (!(Test-Path $zip)) { & curl.exe -fL --retry 2 --silent --show-error $url -o $zip; if ($LASTEXITCODE) { throw "Download failed: $name" } }
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $hash) { throw "Checksum mismatch: $name" }
    if (!(Test-Path (Join-Path $folder '.extracted'))) { New-Item -ItemType Directory -Path $folder -Force | Out-Null; Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force; Set-Content (Join-Path $folder '.extracted') 'verified' }
}
Get-VerifiedArchive 'go.zip' 'https://go.dev/dl/go1.27.1.windows-amd64.zip' 'a3911b5e0e1b1053f25ed0675f4c1c6aad1e2bfcf253df2b9be4caabd2edd95d' (Join-Path $deps 'golang')
Get-VerifiedArchive 'llvm.zip' 'https://download.wireguard.com/windows-toolchain/distfiles/llvm-mingw-20260311-ucrt-x86_64.zip' 'dd4c67d98959479c7be2fb6709ba074475991590848cb9d0eb2620be06b182e1' (Join-Path $deps 'llvm')
Get-VerifiedArchive 'wireguard-nt.zip' 'https://download.wireguard.com/wireguard-nt/wireguard-nt-1.1.zip' 'dceb30a9bc4be48cce0f74160fc88a585a2c2627366e8f846fc6658f9038dace' (Join-Path $deps 'driver')
$env:GOROOT = Join-Path $deps 'golang/go'
$env:GOPATH = Join-Path $deps 'gopath'
$compiler = Get-ChildItem (Join-Path $deps 'llvm') -Filter x86_64-w64-mingw32-gcc.exe -Recurse | Select-Object -First 1
$env:CC = $compiler.FullName
$env:PATH = "$($compiler.DirectoryName);$env:GOROOT\bin;$env:PATH"
$env:GOOS = 'windows'; $env:GOARCH = 'amd64'; $env:CGO_ENABLED = '1'
$native = Join-Path $projectRoot 'app/HateVPN.Service/Native'
New-Item -ItemType Directory -Path $native -Force | Out-Null
& "$env:GOROOT/bin/go.exe" -C $source build -overlay .overlay/overlay.json -buildmode c-shared '-ldflags=-w -s' -trimpath -o (Join-Path $native 'tunnel.dll') ./embeddable-dll-service
if ($LASTEXITCODE) { throw 'WireGuard tunnel build failed' }
Copy-Item -LiteralPath (Join-Path $deps 'driver/wireguard-nt/bin/amd64/wireguard.dll') -Destination $native
Write-Output 'Native WireGuard libraries built and verified.'
