@echo off
rem Test existing SSTP profiles, rank working profiles by download speed, and
rem keep TOP 3 by default (ALL/TOP N available).
rem Deletion happens only after the summary table and an explicit YES.

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-FreeSstpServers_v16_1.ps1" -VerifyExisting -KeepBestExisting
echo.
pause
