@echo off
setlocal
cd /d "%~dp0"
<<<<<<< HEAD
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
=======
where gradle >nul 2>nul
if errorlevel 1 (
  echo Gradle was not found in PATH. Install Gradle and a JDK 17 or newer.
  pause
  exit /b 1
)
gradle test
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
if errorlevel 1 pause
