@echo off
setlocal
cd /d "%~dp0"
where gradle >nul 2>nul
if errorlevel 1 (
  echo Gradle was not found in PATH. Install Gradle and a JDK 17 or newer.
  pause
  exit /b 1
)
gradle test
if errorlevel 1 pause
