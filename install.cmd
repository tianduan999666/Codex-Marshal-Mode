@echo off
setlocal
set "SCRIPT_ROOT=%~dp0"
set "INNER_INSTALL=%SCRIPT_ROOT%codex-home-export\install.cmd"
if not exist "%INNER_INSTALL%" (
  echo [ERROR] Missing codex-home-export\install.cmd
  exit /b 1
)

call "%INNER_INSTALL%" %*
exit /b %ERRORLEVEL%
