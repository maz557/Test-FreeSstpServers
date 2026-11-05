@echo off
rem List existing Windows VPN profiles only. Nothing is dialed or changed.
rem Double-click this file. It requests Administrator rights automatically.

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-FreeSstpServers_v16_1.ps1" -ListExisting
echo.
pause
