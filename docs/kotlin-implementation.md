# Реализация Kotlin

Kotlin-версия является самостоятельным портом бизнес-логики C++ и настольным демонстрационным приложением.

## Стек

- Kotlin JVM 2.1.20, JDK 17+.
- Swing для настольного интерфейса.
- FlatLaf 3.7.2 для современной светлой темы, скруглённых компонентов и аккуратных таблиц.
- Gradle 8.10–8.12.1; рекомендуется Gradle Wrapper `gradlew.bat`.

## Основные модули

- `model/Models.kt` — DTO, транзакции, профиль клиента, scored rows и workflow status.
- `csv/CsvCodec.kt` — чтение/валидация CSV.
- `engine/ScoringEngine.kt` — правила скоринга, медиана, p95 nearest-rank и velocity.
- `service/FraudGuardService.kt` — пакетная обработка.
- `io/ReportWriter.kt` — пакетные отчёты и `operator-decisions.csv`.
- `ui/FraudGuardFrame.kt` — живая лента Swing, очередь REVIEW, решения оператора и запуск C++ batch.
- `LiveTransactionRow.resolveReview()` — единый переход ручной проверки; повторное решение и изменение автоматически закрытых записей запрещены.

## Запуск

```powershell
Set-Location .\kotlin
.\gradlew.bat run
```

Если Wrapper ещё не создавался:

```powershell
gradle wrapper --gradle-version 8.12.1
.\gradlew.bat run
```

## Тесты

```powershell
.\gradlew.bat test
```

JUnit suite проверяет исходный и расширенный golden-набор (15 строк), velocity-окно, точные границы P95 и 5×median, область профиля по клиенту и валюте, CSV quotes/BOM/CRLF, одноразовое решение оператора и формат `operator-decisions.csv`.

## Важное поведение

Исходная рекомендация движка (`APPROVE`, `REVIEW`, `BLOCK`) не перезаписывается ручным решением. `APPROVED_BY_OPERATOR` и `REJECTED_BY_OPERATOR` сохраняются в `operator-decisions.csv`. Вкладка C++ запускает пакетный `.exe` отдельным процессом на desktop-платформе.
