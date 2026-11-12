@echo off
setlocal
cd /d "%~dp0"
if exist gradlew.bat (
  call gradlew.bat test
) else (
  where gradle >nul 2>nul
  if errorlevel 1 (
    echo Gradle Wrapper is missing and Gradle was not found in PATH.
    echo Run: gradle wrapper --gradle-version 8.12.1
    pause
    exit /b 1
  )
  gradle test
)
if errorlevel 1 pause
