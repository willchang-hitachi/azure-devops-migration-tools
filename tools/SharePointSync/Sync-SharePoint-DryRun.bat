@echo off
setlocal
rem Shows the differences between SharePoint and the local folder without downloading anything.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-SharePoint.ps1" -DryRun %*
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
