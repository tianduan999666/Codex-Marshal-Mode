@echo off
setlocal
set "SCRIPT_ROOT=%~dp0"
set "PS_SCRIPT=%SCRIPT_ROOT%rollback-from-backup.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=%SCRIPT_ROOT%config\chancellor-mode\rollback-from-backup.ps1"
if not exist "%PS_SCRIPT%" (
  echo [ERROR] Missing rollback-from-backup.ps1
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
exit /b %ERRORLEVEL%
