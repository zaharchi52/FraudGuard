param(
    [switch]$FetchGoogleTest
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$fetchGTest = if ($FetchGoogleTest) { "ON" } else { "OFF" }

Push-Location $root
try {
    Write-Host "=== FraudGuard: C++ / CTest ===" -ForegroundColor Cyan
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        throw "CMake не найден. Установи CMake и добавь его в PATH."
    }

    cmake -S cpp -B cpp/build -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release `
        -DFRAUDGUARD_USE_GTEST=ON -DFRAUDGUARD_FETCH_GTEST=$fetchGTest
    if ($LASTEXITCODE -ne 0) { throw "CMake configure завершился с кодом $LASTEXITCODE" }

    cmake --build cpp/build --config Release
    if ($LASTEXITCODE -ne 0) { throw "C++ build завершился с кодом $LASTEXITCODE" }

    ctest --test-dir cpp/build -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw "CTest завершился с кодом $LASTEXITCODE" }

    Write-Host "=== FraudGuard: Kotlin / JUnit ===" -ForegroundColor Cyan
    Push-Location (Join-Path $root "kotlin")
    try {
        if (-not (Test-Path ".\gradlew.bat")) {
            throw "Не найден kotlin\gradlew.bat. Создай Gradle Wrapper командой gradle wrapper --gradle-version 8.12.1."
        }
        .\gradlew.bat clean test --rerun-tasks
        if ($LASTEXITCODE -ne 0) { throw "Kotlin tests завершились с кодом $LASTEXITCODE" }
    } finally { Pop-Location }

    Write-Host "=== FraudGuard: Dart / Flutter ===" -ForegroundColor Cyan
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter не найден. Установи Flutter SDK и добавь flutter\bin в PATH."
    }
    Push-Location (Join-Path $root "dart")
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get завершился с кодом $LASTEXITCODE" }

        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze завершился с кодом $LASTEXITCODE" }

        flutter test
        if ($LASTEXITCODE -ne 0) { throw "flutter test завершился с кодом $LASTEXITCODE" }
    } finally { Pop-Location }

    Write-Host "Все автоматические проверки FraudGuard завершились успешно." -ForegroundColor Green
} finally {
    Pop-Location
}
