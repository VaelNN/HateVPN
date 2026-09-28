param([switch]$SkipNative)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    if (!$SkipNative) { & "$PSScriptRoot/prepare-native.ps1"; & "$PSScriptRoot/prepare-amneziawg.ps1" }
    & "$PSScriptRoot/build-icon.ps1"
    & "$PSScriptRoot/build-uninstaller.ps1"
    & "$PSScriptRoot/prepare-xray.ps1"
    & dotnet run --project tests/HateVPN.Tests/HateVPN.Tests.csproj -c Release
    if ($LASTEXITCODE) { throw 'Tests failed' }
    foreach ($item in @(@('Desktop','App'),@('Service','Service'))) {
        & dotnet publish "app/HateVPN.$($item[0])/HateVPN.$($item[0]).csproj" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -o "dist/Release/$($item[1])"
        if ($LASTEXITCODE) { throw 'Publish failed' }
    }
    Copy-Item 'vendor/toolchain/driver/wireguard-nt/LICENSE.txt' 'dist/Release/Service/WireGuardNT-LICENSE.txt'
    Copy-Item 'vendor/awg-windows-source/README.md' 'dist/Release/Service/AmneziaWG-Windows-LICENSE.txt'
    Copy-Item -Force 'vendor/toolchain/gopath/pkg/mod/github.com/amnezia-vpn/amneziawg-go/v3@v3.1.20260814/LICENSE' 'dist/Release/Service/AmneziaWG-Go-LICENSE.txt'
    Copy-Item 'vendor/xray-26.9.9/bin/xray.exe' 'dist/Release/Service/xray.exe'
    Copy-Item 'vendor/xray-26.9.9/bin/wintun.dll' 'dist/Release/Service/wintun.dll'
    Copy-Item 'vendor/xray-26.9.9/bin/LICENSE' 'dist/Release/Service/Xray-LICENSE.txt'
    Copy-Item 'vendor/xray-26.9.9/bin/LICENSE-Wintun' 'dist/Release/Service/Wintun-LICENSE.txt'
    Copy-Item 'licenses/*.txt' 'dist/Release/App/'
    $nativeCheck=Start-Process -FilePath (Join-Path $root 'dist/Release/Service/HateVPN.Service.exe') -ArgumentList '--native-check' -WindowStyle Hidden -Wait -PassThru
    if ($nativeCheck.ExitCode) { throw 'Native engine check failed' }
    $wix=Join-Path $root 'vendor/wix5/wix.exe'
    if (!(Test-Path $wix)) { & dotnet tool install wix --version 5.0.2 --tool-path vendor/wix5; if ($LASTEXITCODE) { throw 'WiX installation failed' } }
    $env:DOTNET_ROLL_FORWARD='Major'
    & $wix extension add WixToolset.UI.wixext/5.0.2 --global
    if ($LASTEXITCODE) { throw 'WiX UI extension failed' }
    & $wix extension add WixToolset.Util.wixext/5.0.2 --global
    if ($LASTEXITCODE) { throw 'WiX Util extension failed' }
    & $wix build installer/HateVPN.wxs -arch x64 -culture ru-ru -ext WixToolset.UI.wixext -ext WixToolset.Util.wixext -d "Root=$root" -o dist/HateVPN-1.0-x64.msi
    if ($LASTEXITCODE) { throw 'Installer build failed' }
    & dotnet publish app/HateVPN.Setup/HateVPN.Setup.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -o dist/Release/Setup
    if ($LASTEXITCODE) { throw 'Setup launcher publish failed' }
    Copy-Item 'dist/Release/Setup/HateVPN.Setup.exe' 'dist/HateVPN-1.0-Setup.exe' -Force
    Get-FileHash dist/HateVPN-1.0-Setup.exe -Algorithm SHA256 | Format-List
    Get-FileHash dist/HateVPN-1.0-x64.msi -Algorithm SHA256 | Format-List
} finally { Pop-Location }
