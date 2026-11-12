<<<<<<< HEAD
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

## Важное поведение

Исходная рекомендация движка (`APPROVE`, `REVIEW`, `BLOCK`) не перезаписывается ручным решением. `APPROVED_BY_OPERATOR` и `REJECTED_BY_OPERATOR` сохраняются в `operator-decisions.csv`. Вкладка C++ запускает пакетный `.exe` отдельным процессом на desktop-платформе.
=======
# Этап 4. Kotlin-порт и интерактивный интерфейс

## Назначение

Kotlin-реализация повторяет бизнес-логику C++ и добавляет настольный UI на Swing. Живая лента — **симуляция**: строки из `transactions.csv` отображаются постепенно. Никакие реальные платежи не принимаются и не отклоняются.

## Состав реализации

- `model/Models.kt` — транзакции, профиль клиента, факторы риска, результаты и ошибки.
- `csv/CsvCodec.kt` — чтение/валидация входного CSV и экранирование выходных строк.
- `engine/ScoringEngine.kt` — медиана, p95 nearest-rank, velocity count, факторы и итоговое решение.
- `service/FraudGuardService.kt` — загрузка истории и новых транзакций, обработка ошибок и запуск пакетного анализа.
- `io/ReportWriter.kt` — `results.csv`, `alerts.csv`, `errors.csv` и журнал операторских решений.
- `ui/FraudGuardFrame.kt` — выбор файлов, живая лента, пауза, очередь `REVIEW`, действия оператора и запуск собранного C++.

## Алгоритм

1. История группируется по `client_id` и `currency`.
2. При 0 строках профиль имеет статус `COLD_START`; при 1–4 строках — `LIMITED_HISTORY`; от 5 строк — `READY`.
3. Для `READY` рассчитываются медиана и p95 nearest-rank. Правила суммы, новой страны, устройства и категории активны только для `READY`.
4. `HIGH_VELOCITY` срабатывает при 5 и более транзакциях того же клиента в включительном окне от `timestamp - 10 минут` до `timestamp`.
5. Факторы прибавляют баллы: `HIGH_AMOUNT` +30, `UNUSUAL_AMOUNT` +15 (взаимоисключающее правило), `HIGH_VELOCITY` +25, `NEW_COUNTRY` +20, `NEW_DEVICE` +15, `NEW_CATEGORY` +10. Итог ограничен 100.
6. Решение: 0–29 `APPROVE`, 30–59 `REVIEW`, 60–100 `BLOCK`.

## Поток и ручная проверка

Kotlin заранее вычисляет детерминированный результат для CSV-набора, затем воспроизводит транзакции в UI с заданным интервалом. Это позволяет тестировать повторяемый сценарий. Для каждой операции отдельно хранится рекомендация двигателя и workflow-статус:

- `AUTO_APPROVED` — движок рекомендовал `APPROVE`;
- `PENDING_REVIEW` — ждёт ручного решения;
- `AUTO_BLOCKED` — движок рекомендовал `BLOCK`;
- `APPROVED_BY_OPERATOR` — оператор одобрил запись из `REVIEW`;
- `REJECTED_BY_OPERATOR` — оператор отклонил запись из `REVIEW`.

Решения оператора записываются в `operator-decisions.csv`. Изначальная рекомендация движка остаётся нетронутой для аудита.

## Запуск и тесты в Windows / VS Code

Требуются JDK 17+ и Gradle 8.10–8.12.1. Из терминала VS Code:

```powershell
Set-Location .\kotlin
gradle run
gradle test
```

Или используйте `Terminal → Run Task` → `FraudGuard: Run Kotlin GUI` / `FraudGuard: Test Kotlin engine`.

Тест `ScoringEngineTest` сверяет score, decision, risk factors и profile status с `data/expected-results.csv`. Дополнительные тесты проверяют правила CSV-кавычек, cold-start и пороги решений.

## Запуск C++ из интерфейса

Кнопка `Запустить C++ batch` ищет исполняемый файл в `cpp/build/Release/fraudguard.exe`, `cpp/build/fraudguard.exe` и соответствующих путях без `.exe` для Unix. Отчёты C++ сохраняются в подкаталог `cpp-batch` выбранной папки отчётов.

## Ограничения учебного MVP

- Лента читает заранее подготовленный CSV, а не подключается к банковскому брокеру сообщений.
- Решение оператора не меняет задним числом исходный риск-скор.
- `BLOCK` является автоматической рекомендацией прототипа; интеграции с платёжной системой нет.
- Параметры скоринга — учебные, не предназначены для реальных финансовых решений.
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
