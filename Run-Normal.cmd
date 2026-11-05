@echo off
rem Normal server test using the clipboard list (v16 engine).
rem Adjust the parameters below if you want another source or a different limit.

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-FreeSstpServers_v16_1.ps1" -UseClipboard -PortMode Non443 -MaxServers 30 -AddBestVpnCount 3
echo.
pause
