# FraudGuard — анти-фрод скоринг-движок

Учебный консольный прототип для анализа синтетических транзакций: правила + статистический профиль клиента → риск-скор 0–100 → `APPROVE` / `REVIEW` / `BLOCK` → отчёты CSV.

> Это учебная модель, не предназначенная для реальных платёжных решений. Все данные в каталоге `data/` синтетические.

## Документы

1. [`VISION.md`](VISION.md) — видение и цели проекта.
2. [`docs/requirements.md`](docs/requirements.md) — требования, пользовательские истории и критерии приёмки.
3. [`docs/architecture.md`](docs/architecture.md) — архитектура модулей.
4. [`docs/uml/`](docs/uml/) — три исходника UML в PlantUML.
5. [`docs/csv-schema.md`](docs/csv-schema.md) — контракт входных и выходных CSV.
6. [`docs/cpp-implementation.md`](docs/cpp-implementation.md) — пояснение реализации C++ и результаты проверки.

## Сборка и запуск C++

Из корня репозитория с установленными CMake и компилятором C++17 выполните:

```bash
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build --config Release
ctest --test-dir cpp/build --output-on-failure
./cpp/build/fraudguard --transactions data/transactions.csv --history data/history.csv --out-dir reports
```

Для Windows см. [`cpp/README.md`](cpp/README.md). CMake использует Google Test, если он установлен; иначе запускает автономные smoke-тесты.

Результаты сохраняются в `reports/results.csv`, алерты `REVIEW`/`BLOCK` — в `reports/alerts.csv`, диагностика — в `reports/errors.csv`. Для проверки ошибок строк запустите приложение с `data/transactions_invalid.csv`.

## Правила скоринга

- `HIGH_AMOUNT`: +30.
- `UNUSUAL_AMOUNT`: +15, взаимоисключающее с `HIGH_AMOUNT`.
- `HIGH_VELOCITY`: +25.
- `NEW_COUNTRY`: +20.
- `NEW_DEVICE`: +15.
- `NEW_CATEGORY`: +10.

`MIN_HISTORY_SIZE = 5`; сумма факторов ограничивается 100. Решения: 0–29 `APPROVE`, 30–59 `REVIEW`, 60–100 `BLOCK`. Точные условия определены в `docs/requirements.md`.

## Структура

- `docs/` — требования, проектирование, UML, сценарии и решения команды.
- `data/` — синтетические входные данные и эталонные результаты.
- `cpp/` — C++17-ядро, CSV-ввод/вывод, CMake и тесты.
- `kotlin/` — Kotlin-порт бизнес-логики на этапе 4.
- `reports/` — создаваемые программой CSV-отчёты (не добавляются в Git).

## Статус работ

- [x] Этап 1: требования и синтетические данные.
- [x] Этап 2: архитектура и UML.
- [x] Этап 3: рабочее ядро C++17 и CSV-отчёты.
- [ ] Этап 4: Kotlin-порт и сравнение.
- [ ] Этап 5: расширенный набор unit- и граничных тестов, отчёт о дефектах.
- [ ] Этап 6: Git-история команды, README финальной версии и презентация на 7–10 минут.
