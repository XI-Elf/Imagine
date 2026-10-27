@echo off
setlocal
cd /d "%~dp0"
set "HEX_ENGINE=%~dp0_runtime\AmberWorldRuntime.exe"
if not exist "%HEX_ENGINE%" (
  echo Missing bundled runtime. Extract the entire ZIP first.
  pause
  exit /b 1
)
"%HEX_ENGINE%" --headless --editor --path "%~dp0game" --import --quit > "%~dp0HEX_import.log" 2>&1
if errorlevel 1 (
  start notepad.exe "%~dp0HEX_import.log"
  exit /b 1
)
start "Amber World HEX" "%HEX_ENGINE%" --path "%~dp0game"
