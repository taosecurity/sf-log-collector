@echo off
rem Double-click after playing (after quitting Starfield). Options: see README.md.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-StarfieldTestLogs.ps1" %*
set rc=%errorlevel%
echo.
pause
exit /b %rc%
