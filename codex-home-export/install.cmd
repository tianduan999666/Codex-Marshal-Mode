@echo off
setlocal
set "SCRIPT_ROOT=%~dp0"
set "PS_SCRIPT=%SCRIPT_ROOT%run-managed-install.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=%SCRIPT_ROOT%config\marshal-mode\run-managed-install.ps1"
if not exist "%PS_SCRIPT%" (
  echo [ERROR] Missing run-managed-install.ps1
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
exit /b %ERRORLEVEL%
