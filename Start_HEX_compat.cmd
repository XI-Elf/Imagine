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
start "Amber World HEX (compat)" "%HEX_ENGINE%" --rendering-method gl_compatibility --rendering-driver opengl3 --path "%~dp0game"
