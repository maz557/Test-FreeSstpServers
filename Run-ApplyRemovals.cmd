@echo off
rem Test existing SSTP profiles and remove rejected ones.
rem Deletion happens only after the summary table and an explicit YES.

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-FreeSstpServers_v16_1.ps1" -VerifyExisting
echo.
pause
