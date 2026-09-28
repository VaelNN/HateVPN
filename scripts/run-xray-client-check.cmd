@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose-xray-client.ps1"
echo.
echo Send me the new HateVPN-Xray-client-*.txt file from this folder.
pause
