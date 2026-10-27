@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
rem ============================================================================
rem  Amber World: сборка отдельной версии (без Godot), которую можно отдать другому игроку.
rem  Результат: папка dist\AmberWorld (AmberWorld.exe одним файлом) и архив AmberWorld_Standalone.zip.
rem  Нужен интернет только для первой сборки (шаблоны экспорта Godot скачиваются один раз).
rem ============================================================================

set "PROJECT=%~dp0game"
set "ENGINE="
if exist "%~dp0_runtime\Godot.exe" set "ENGINE=%~dp0_runtime\Godot.exe"
if not defined ENGINE if exist "%PROJECT%\_runtime\Godot.exe" set "ENGINE=%PROJECT%\_runtime\Godot.exe"
if not defined ENGINE if defined GODOT set "ENGINE=%GODOT%"
if not defined ENGINE (
    echo Не найден Godot. Один раз запустите AmberWorld.exe, он скачает рабочую копию в папку _runtime,
    echo или задайте путь переменной GODOT, например: set GODOT=C:\Godot\Godot.exe
    pause
    exit /b 1
)
echo Движок: %ENGINE%

rem --- версия движка и папка шаблонов экспорта ---
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "$v=(& '%ENGINE%' --version); if ($v -match '^([0-9]+(\.[0-9]+)*\.(stable|beta[0-9]*|rc[0-9]*|dev[0-9]*))') { $matches[1] } else { 'unknown' }"`) do set "GVER=%%V"
echo Версия: %GVER%
set "TPL=%APPDATA%\Godot\export_templates\%GVER%"
if not exist "%TPL%\windows_release_x86_64.exe" (
    echo Шаблоны экспорта не найдены, скачиваю официальные, около 1 ГБ, один раз...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';" ^
      "$ver=('%GVER%' -replace '\.(stable|beta[0-9]*|rc[0-9]*|dev[0-9]*)$','');" ^
      "$zip=Join-Path $env:TEMP 'aw_templates.zip'; $dir=Join-Path $env:TEMP 'aw_templates';" ^
      "Invoke-WebRequest -UseBasicParsing -Uri ('https://downloads.godotengine.org/?flavor=stable&platform=templates&slug=export_templates.tpz&version=' + $ver) -OutFile $zip;" ^
      "if (Test-Path $dir) { Remove-Item -Recurse -Force $dir };" ^
      "Expand-Archive -Force -Path $zip -DestinationPath $dir;" ^
      "New-Item -ItemType Directory -Force -Path '%TPL%' | Out-Null;" ^
      "Copy-Item -Force -Path (Join-Path $dir 'templates\*') -Destination '%TPL%';" ^
      "Remove-Item -Force $zip; Remove-Item -Recurse -Force $dir"
    if errorlevel 1 (
        echo.
        echo Не удалось скачать шаблоны. Откройте проект в редакторе Godot, выберите
        echo Редактор - Управление шаблонами экспорта - Скачать и установить, потом запустите этот файл снова.
        pause
        exit /b 2
    )
)

rem --- импорт ресурсов и экспорт ---
echo Импорт ресурсов...
"%ENGINE%" --headless --path "%PROJECT%" --import
set "OUT=%~dp0dist\AmberWorld"
if exist "%~dp0dist" rmdir /s /q "%~dp0dist"
mkdir "%OUT%"
echo Экспорт игры...
"%ENGINE%" --headless --path "%PROJECT%" --export-release "Windows Desktop" "%OUT%\AmberWorld.exe"
if not exist "%OUT%\AmberWorld.exe" (
    echo.
    echo Экспорт не удался. Прочитайте сообщения выше, проверьте шаблоны экспорта и файл game\export_presets.cfg.
    pause
    exit /b 3
)

rem --- архив для передачи ---
> "%OUT%\ЗАПУСК.txt" echo Распакуйте архив целиком и запустите AmberWorld.exe. Godot устанавливать не нужно.
powershell -NoProfile -Command "Compress-Archive -Force -Path '%OUT%' -DestinationPath '%~dp0AmberWorld_Standalone.zip'"
echo.
echo Готово: %~dp0AmberWorld_Standalone.zip
echo Это отдельная версия: Godot и интернет получателю не нужны.
pause
