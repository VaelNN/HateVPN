$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = Join-Path $projectRoot 'vendor/awg-windows-source'
$revision = 'e90531d15802cb976773f3b63443bc281f738ca3'
if (!(Test-Path (Join-Path $source '.git'))) {
    & git clone https://github.com/amnezia-vpn/amneziawg-windows.git $source
    if ($LASTEXITCODE) { throw 'AmneziaWG checkout failed' }
    & git -C $source checkout --detach $revision
    if ($LASTEXITCODE) { throw 'AmneziaWG revision unavailable' }
}
if ((& git -C $source rev-parse HEAD) -ne $revision) { throw 'Unexpected AmneziaWG source revision' }
$deps = Join-Path $projectRoot 'vendor/toolchain'
$env:GOROOT = Join-Path $deps 'golang/go'
$env:GOPATH = Join-Path $deps 'gopath'
$compiler = Get-ChildItem (Join-Path $deps 'llvm') -Filter x86_64-w64-mingw32-gcc.exe -Recurse | Select-Object -First 1
if (!$compiler) { throw 'Run prepare-native.ps1 first to install the compiler' }
$env:CC = $compiler.FullName
$env:PATH = "$($compiler.DirectoryName);$env:GOROOT\bin;$env:PATH"
$env:GOOS = 'windows'; $env:GOARCH = 'amd64'; $env:CGO_ENABLED = '1'
$native = Join-Path $projectRoot 'app/HateVPN.Service/Native'
New-Item -ItemType Directory -Path $native -Force | Out-Null
& "$env:GOROOT/bin/go.exe" -C $source build -buildmode c-shared '-ldflags=-w -s' -trimpath -o (Join-Path $native 'amneziawg-tunnel.dll') .
if ($LASTEXITCODE) { throw 'AmneziaWG tunnel build failed' }
Write-Output 'Native AmneziaWG library built.'
