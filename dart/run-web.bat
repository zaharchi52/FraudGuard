@echo off
setlocal
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter SDK was not found in PATH.
  echo Install Flutter stable and enable Chrome web support.
  echo Then run: flutter doctor -v
  pause
  exit /b 1
)
flutter pub get
if errorlevel 1 goto :error
flutter run -d chrome
if errorlevel 1 goto :error
exit /b 0
:error
pause
exit /b 1
