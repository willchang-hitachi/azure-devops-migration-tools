@echo off
setlocal
rem Runs Sync-SharePoint.ps1 with the execution policy bypassed for this run only.
rem Any arguments are passed through, e.g.:  Sync-SharePoint.bat -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-SharePoint.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
