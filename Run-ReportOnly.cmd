@echo off
rem Test existing SSTP profiles in REPORT-ONLY mode.
rem Nothing is deleted. This is the recommended first maintenance run.

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-FreeSstpServers_v16_1.ps1" -VerifyExisting -ReportOnly
echo.
pause
