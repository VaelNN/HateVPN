$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is unavailable' }
$output=Join-Path $root 'dist\Release\Uninstall\HateVPN.Uninstall.exe'
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
& $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll "/win32icon:$root\app\HateVPN.Desktop\Assets\HateVPN.ico" "/out:$output" "$root\app\HateVPN.Uninstall\Program.cs"
if ($LASTEXITCODE) { throw 'Uninstaller build failed' }
