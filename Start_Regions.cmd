@echo off
rem Region viewer from sources (needs Godot 4.7: godot in PATH or Godot.exe next to this file)
cd /d "%~dp0"
where godot >NUL 2>NUL && (godot --path game res://region_viewer.tscn & goto :eof)
if exist "%~dp0Godot.exe" ("%~dp0Godot.exe" --path game res://region_viewer.tscn & goto :eof)
echo Godot 4.7 not found. Put Godot.exe next to this file.
pause
