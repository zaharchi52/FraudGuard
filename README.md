# FraudGuard — анти-фрод скоринг-движок

Учебный проект: C++17-движок пакетного анализа, Kotlin/Swing desktop-приложение и Dart/Flutter Web-интерфейс с имитацией живой ленты и ручной очередью проверки. Все данные синтетические; подключение к реальным платёжным системам отсутствует.
Учебный проект: C++17-движок пакетного анализа и Kotlin/Swing-приложение с имитацией живой ленты и ручной очередью проверки. Все данные синтетические; подключение к реальным платёжным системам отсутствует.


## Возможности

- Профиль клиента: медиана, 95-й перцентиль, история по клиенту и валюте.
- Шесть антифрод-факторов, риск-скор 0–100 и рекомендации `APPROVE` / `REVIEW` / `BLOCK`.
- CSV-ввод/вывод и запись ошибок некорректных строк.
- Kotlin-порт для сопоставления с C++ и desktop GUI на Swing + FlatLaf.
- Dart-порт на Flutter Web: браузерная панель мониторинга, имитация потока, ручная очередь `REVIEW` и CSV-экспорт.
- Кнопка запуска C++ batch-движка из Kotlin Desktop.
- Сверка результатов Dart с общим эталонным `expected-results.csv`.

## Эталонные данные

- `data/expected-results.csv` — исходный golden-набор (9 операций).
- `data/conformance/` — расширенный общий golden-набор (15 операций) для сверки C++, Kotlin и Dart.
- Kotlin-порт для сопоставления с C++.
- Swing GUI: имитированная лента, пауза, очередь `REVIEW`, действия оператора и журнал.
- Кнопка запуска C++ batch-движка из окна приложения.

## Документы

- [`VISION.md`](VISION.md) — видение проекта.
- [`docs/requirements.md`](docs/requirements.md) — требования и критерии приёмки.
- [`docs/architecture.md`](docs/architecture.md) — архитектура.
- [`docs/uml/`](docs/uml/) — PlantUML: Use Case, Class и Sequence.
- [`docs/csv-schema.md`](docs/csv-schema.md) — контракт CSV.
- [`docs/cpp-implementation.md`](docs/cpp-implementation.md) — реализация C++.
- [`docs/kotlin-implementation.md`](docs/kotlin-implementation.md) — Kotlin, GUI и операторская очередь.
- [`docs/dart-implementation.md`](docs/dart-implementation.md) — Dart/Flutter Web, CSV, скоринг и браузерные ограничения.
<<<<<<< HEAD
- [`docs/test-plan.md`](docs/test-plan.md) — план и стратегия тестирования.
- [`docs/testing-frameworks.md`](docs/testing-frameworks.md) — чем отличаются Google Test, CTest, JUnit 5 и Flutter Test и как запускать их.
- [`docs/cross-language-conformance.md`](docs/cross-language-conformance.md) — сверка C++ / Kotlin / Dart по общим эталонным данным.
- [`docs/manual-acceptance-tests.md`](docs/manual-acceptance-tests.md) — ручная проверка Kotlin и Dart GUI.
- [`docs/defect-report.md`](docs/defect-report.md) — журнал найденных дефектов и шаблон.
- [`docs/qa-results.md`](docs/qa-results.md) — результаты проведённого QA-прогона и ограничения окружения.
- [`docs/stage5-install.md`](docs/stage5-install.md) — установка обновления этапа 5 и фиксация в Git.

## C++

В PowerShell из корня репозитория:

```powershell
cmake -S cpp -B cpp/build
cmake --build cpp/build --config Release
ctest --test-dir cpp/build -C Release --output-on-failure
.\cpp\build\Release\fraudguard.exe --transactions data/transactions.csv --history data/history.csv --out-dir reports
```

## Kotlin GUI

Требуются JDK 17+ и Gradle 8.10–8.12.1. В терминале VS Code:

```powershell
Set-Location .\kotlin
.\gradlew.bat run
=======
gradle run
```

Запуск тестов Kotlin:

```powershell
.\gradlew.bat test
```

Также доступны задачи VS Code из `Terminal → Run Task`: `FraudGuard: Run Kotlin GUI` и `FraudGuard: Test Kotlin engine`. Для Kotlin используется локальный `gradlew.bat`, поэтому глобально установленный Gradle не требуется. Подробнее — [`kotlin/README.md`](kotlin/README.md).

## Dart / Flutter Web

Требуются Flutter stable с Dart SDK 3.10+ и Chrome/Edge. В терминале VS Code:

```powershell
Set-Location .\dart
flutter pub get
flutter run -d chrome
```

Тесты и статический анализ:

```powershell
flutter test
flutter analyze
```

Для запуска всех автоматических проверок подряд из корня проекта:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\run-all-tests.ps1 -FetchGoogleTest
```

Флаг `-FetchGoogleTest` включает загрузку Google Test при первом C++-прогоне. Без него C++ проверяется доступным smoke/integration-тестом; см. [`docs/testing-frameworks.md`](docs/testing-frameworks.md).
Или в VS Code: `Terminal → Run Task → FraudGuard: Run all tests`.

Сборка статического сайта:

```powershell
flutter build web --release
```

Готовая сборка находится в `dart/build/web`. В VS Code доступны задачи `FraudGuard Dart: Get Packages`, `Run Web (Chrome)`, `Test`, `Analyze` и `Build Web`. Подробнее — [`dart/README.md`](dart/README.md). Браузерная версия обрабатывает выбранные файлы локально и не может запускать пользовательский C++ `.exe`; для этого используется Kotlin Desktop или CLI.


Также доступны задачи VS Code из `Terminal → Run Task`: `FraudGuard: Run Kotlin GUI` и `FraudGuard: Test Kotlin engine`. Подробнее — [`kotlin/README.md`](kotlin/README.md).

## Выходные файлы

- `reports/results.csv`, `alerts.csv`, `errors.csv` — C++ batch-отчёты.
- `reports-kotlin/results.csv`, `alerts.csv`, `errors.csv` — Kotlin batch-отчёты.
- `reports-kotlin/operator-decisions.csv` — статусы показа и решения оператора.
- `reports-kotlin/cpp-batch/` — batch-отчёты C++ при запуске из GUI.
- Dart Web скачивает экспортированные CSV через браузерный диалог/загрузки.

## Правила скоринга

`HIGH_AMOUNT` +30; `UNUSUAL_AMOUNT` +15 (взаимоисключающий фактор); `HIGH_VELOCITY` +25; `NEW_COUNTRY` +20; `NEW_DEVICE` +15; `NEW_CATEGORY` +10. Минимум истории — 5 операций. Решения: 0–29 `APPROVE`, 30–59 `REVIEW`, 60–100 `BLOCK`.

## Статус этапов

- [x] Этап 1: требования и данные.
- [x] Этап 2: проектирование и UML.
- [x] Этап 3: C++17-ядро и отчёты.
- [x] Этап 4: Kotlin-порт, Swing GUI, Dart-порт и Flutter Web UI.
- [x] Этап 5: расширенное тестирование, граничные случаи и отчёт о дефектах.
- [x] Этап 6: PR/история Git, финальная документация и презентация.

