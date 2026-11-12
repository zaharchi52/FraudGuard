@echo off
setlocal
cd /d "%~dp0"
where gradle >nul 2>nul
if errorlevel 1 (
  echo Gradle was not found in PATH.
  echo Install Gradle and a JDK 17 or newer, then reopen VS Code.
  echo See README.md in this folder for instructions.
  pause
  exit /b 1
)
gradle run
if errorlevel 1 pause
