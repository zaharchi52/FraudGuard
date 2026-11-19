# План тестирования FraudGuard

## 1. Цель

Проверить корректность скоринга, чтения CSV, формирования отчётов и ручной проверки, а также убедиться, что C++, Kotlin и Dart дают одинаковые результаты на общих синтетических данных.

## 2. Инструменты

| Часть проекта | Инструмент | Назначение |
|---|---|---|
| C++ unit tests | Google Test | Проверка отдельных функций: статистика, правила, границы и даты |
| C++ integration/smoke | Собственные проверки + CTest | Проверка пакетной обработки, CSV и эталонных отчётов |
| Kotlin | JUnit 5 + `kotlin.test` | Unit-тесты скоринга, CSV, ручной проверки и записи отчётов |
| Dart | `flutter_test` | Дополнительные unit-тесты Flutter/Dart |
| Dart static analysis | `flutter analyze` | Статический анализ, не unit-тест |
| GUI | Ручные приёмочные сценарии | Проверка окон, живой ленты, REVIEW и экспорта |
| Межъязыковая сверка | Golden CSV fixtures | Сравнение результата каждой реализации с общим эталоном |

Подробное объяснение инструментов и команд находится в [`testing-frameworks.md`](testing-frameworks.md).

## 3. Уровни тестирования

1. **Unit:** медиана, P95, пороги решений, отдельные правила, CSV-парсер, переход состояния REVIEW.
2. **Integration:** чтение CSV, построение профиля, скоринг, запись `results.csv`, `alerts.csv`, `errors.csv`.
3. **Cross-language conformance:** C++, Kotlin и Dart сравниваются с общими эталонными CSV.
4. **Manual acceptance:** пользовательские действия в Kotlin Desktop и Dart Web.
5. **Regression:** повторный запуск теста после исправления дефекта.

## 4. Тестовые данные

- `data/transactions.csv` + `data/history.csv` + `data/expected-results.csv` — базовый набор (9 новых транзакций).
- `data/conformance/` — расширенный набор (15 транзакций), который проверяет статусы профиля, валюты, граничные суммы и временное окно velocity.
- `data/transactions_invalid.csv` — ошибочные строки и корректная строка после них.

Данные синтетические и не содержат настоящих платёжных сведений.

## 5. Основные проверки

| Проверка | Ожидаемый результат |
|---|---|
| Медиана для нечётного и чётного количества значений | Центральное значение или среднее двух центральных |
| P95 | Метод ближайшего ранга |
| Сумма ровно равна P95 | `UNUSUAL_AMOUNT` не срабатывает |
| Сумма равна 5 × медиана | `HIGH_AMOUNT` срабатывает |
| Пятая операция за 10 минут | `HIGH_VELOCITY` срабатывает |
| История 0 / 1–4 / 5+ | `COLD_START` / `LIMITED_HISTORY` / `READY` |
| Скор 29 / 30 / 59 / 60 / 100 | `APPROVE` / `REVIEW` / `REVIEW` / `BLOCK` / `BLOCK` |
| Сумма баллов больше 100 | Скор ограничивается 100 |
| Дубликат ID или некорректный CSV | Строка отклоняется, причина сохраняется |
| Ошибка в одной строке | Следующая корректная строка всё равно обрабатывается |
| Оператор одобряет/отклоняет REVIEW | Сохраняется отдельное операторское решение |

## 6. Критерии завершения

- C++ собран в Release, CTest прошёл.
- Google Test cases собраны и запущены; если GTest недоступен, это явно отмечено как ограничение, а не как успешный запуск GTest.
- Kotlin `clean test --rerun-tasks` прошёл, HTML-отчёт Gradle сохранён.
- `flutter analyze` не сообщает ошибок/предупреждений, требующих исправления; `flutter test` прошёл.
- 15 строк расширенного golden-набора совпадают с ожидаемыми результатами по ID, score, decision, factors и profile status.
- Ручные сценарии двух GUI отмечены `PASS` или зарегистрированы как дефекты.
- Каждый исправленный дефект повторно проверен.

## 7. Команды запуска

Из корня репозитория:

```powershell
cmake -S cpp -B cpp/build -DBUILD_TESTING=ON -DFRAUDGUARD_USE_GTEST=ON -DFRAUDGUARD_FETCH_GTEST=ON
cmake --build cpp/build --config Release
ctest --test-dir cpp/build -C Release --output-on-failure

Set-Location .\kotlin
.\gradlew.bat clean test --rerun-tasks

Set-Location ..\dart
flutter pub get
flutter analyze
flutter test
```

Или весь прогон одним сценарием с загрузкой Google Test:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\run-all-tests.ps1 -FetchGoogleTest
```

Ручные GUI-проверки описаны в [`manual-acceptance-tests.md`](manual-acceptance-tests.md).
