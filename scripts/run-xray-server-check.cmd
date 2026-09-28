@echo off
setlocal
chcp 65001 >nul
set "REPORT=%~dp0HateVPN-Xray-report.txt"
set "SCRIPT=%~dp0diagnose-xray-server.sh"
if not exist "%SCRIPT%" (
  echo Diagnostic script not found: %SCRIPT%
  pause
  exit /b 1
)
set /p "SERVER_HOST=VPS IP address: "
if "%SERVER_HOST%"=="" exit /b 1
set /p "SSH_PORT=SSH port [22]: "
if "%SSH_PORT%"=="" set "SSH_PORT=22"
set "BIND_ARG="
for /f "delims=" %%I in ('powershell.exe -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias HateVPNAWG -ErrorAction SilentlyContinue ^| Select-Object -First 1 -ExpandProperty IPAddress"') do set "BIND_ARG=-b %%I"
echo Checking Xray on %SERVER_HOST%. Your SSH password is not saved.
ssh %BIND_ARG% -o StrictHostKeyChecking=ask -o ConnectTimeout=12 -p %SSH_PORT% "root@%SERVER_HOST%" "bash -s" < "%SCRIPT%" > "%REPORT%"
if errorlevel 1 (
  echo SSH connection failed. No changes were made to the VPS.
) else (
  echo Report saved: %REPORT%
)
pause

