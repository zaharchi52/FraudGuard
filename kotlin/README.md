# FraudGuard Kotlin: интерактивная версия

Kotlin-порт антифрод-скоринга с настольным интерфейсом на Swing и FlatLaf (светлая современная тема, KPI-карточки, цветные статусы и таблицы). Все операции — учебная симуляция на синтетических CSV-данных; приложение не подключается к платёжным системам.

## Требования

- JDK 17 или новее.
- Gradle 8.10–8.12.1 через `gradlew.bat` (предпочтительно) или в `PATH` для ручной установки.
- При первом запуске нужен доступ к Maven Central, чтобы Gradle загрузил Kotlin-плагин и JUnit.

Проверьте в терминале VS Code:

```powershell
java -version
.\gradlew.bat --version
```

Если Wrapper ещё не создан, создайте его командой `gradle wrapper --gradle-version 8.12.1`. Для JDK используйте Temurin 17 или новее и полностью перезапустите VS Code после установки. После установки откройте проект именно из корневой папки `FraudGuard`.

## Запуск интерфейса

Из терминала в корне репозитория:

```powershell
Set-Location .\kotlin
.\gradlew.bat run
```

Если Gradle Wrapper ещё не создан, один раз выполните `gradle wrapper --gradle-version 8.12.1`, затем используйте `gradlew.bat`.

Или двойным щелчком запустите `kotlin\run.bat` из Проводника. В VS Code доступна задача **FraudGuard: Run Kotlin GUI** через `Terminal → Run Task`.

## Проверка Kotlin

```powershell
Set-Location .\kotlin
.\gradlew.bat test
```

Также доступна задача VS Code **FraudGuard: Test Kotlin engine**. Тест `Kotlin port matches C++ expected results fixture` сравнивает баллы, решения, факторы и статус профиля с `data/expected-results.csv`.

## Работа с интерфейсом

1. Укажите `transactions.csv`, `history.csv` и папку отчётов. По умолчанию используются `data/transactions.csv`, `data/history.csv` и `reports-kotlin`.
2. Нажмите **Старт ленты**. Программа загружает CSV, рассчитывает результаты и затем показывает транзакции постепенно с заданным интервалом.
3. `APPROVE` проходит автоматически, `BLOCK` получает статус автоматической блокировки, а `REVIEW` появляется в очереди ручной проверки.
4. Выберите запись в очереди и нажмите **Одобрить выбранную** или **Отклонить выбранную**. В исходном скоринге сохраняется рекомендация движка; решение оператора фиксируется отдельно.
5. **Запустить C++ batch** запускает собранный C++-исполняемый файл, если он найден в стандартной папке `cpp/build/Release/` или `cpp/build/`.

## Файлы отчётов

- `reports-kotlin/results.csv` — пакетный результат Kotlin-скоринга.
- `reports-kotlin/alerts.csv` — исходные рекомендации `REVIEW` и `BLOCK`.
- `reports-kotlin/errors.csv` — ошибочные строки и файл-level ошибки.
- `reports-kotlin/operator-decisions.csv` — статус каждой показанной транзакции и действия оператора.
- `reports-kotlin/cpp-batch/` — отчёты, созданные при запуске C++ из интерфейса.

## Эквивалентность с C++

Kotlin использует тот же порядок факторов, те же веса и пороги, `MIN_HISTORY_SIZE = 5`, p95 по nearest-rank и включительное velocity-окно `[timestamp - 10 минут, timestamp]`. У `APPROVE`, `REVIEW` и `BLOCK` сохраняются те же пороги: 0–29, 30–59 и 60–100. Kotlin-тест проверяет эталонный набор проекта.
