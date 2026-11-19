# Межъязыковая сверка C++ / Kotlin / Dart

## Общий контракт

Для одинакового входного CSV все реализации должны совпадать по следующим полям: `transaction_id`, `risk_score`, `decision`, `risk_factors`, `profile_status`.

| Константа / правило | Значение |
|---|---|
| Минимальный профиль | 5 валидных исторических операций клиента в той же валюте |
| HIGH_AMOUNT | сумма `>= 5 × median`, +30 |
| UNUSUAL_AMOUNT | сумма `> P95` и ниже порога HIGH_AMOUNT, +15 |
| HIGH_VELOCITY | не менее 5 операций в окне `[timestamp - 10 минут, timestamp]`, +25 |
| NEW_COUNTRY | +20, только при READY |
| NEW_DEVICE | +15, только при READY |
| NEW_CATEGORY | +10, только при READY |
| Решение | 0–29 APPROVE; 30–59 REVIEW; 60–100 BLOCK |
| Верхняя граница | score ограничен 100 |
| P95 | nearest-rank |

Профиль строится отдельно для пары `(client_id, currency)`. Velocity в текущей версии считается по клиенту и времени для всех валидных текущих транзакций независимо от порядка строк во входном файле.

## Golden datasets

1. Базовый: `data/history.csv`, `data/transactions.csv`, `data/expected-results.csv`.
2. Расширенный: `data/conformance/history.csv`, `data/conformance/transactions.csv`, `data/conformance/expected-results.csv`.

Расширенный набор намеренно содержит неупорядоченные временные метки, две валюты одного клиента, ограниченную и отсутствующую историю, точные пороги P95 / 5×median и velocity на границе десяти минут.

## Как сравниваются результаты

- C++: smoke-тест запускает пакетную функцию `run()` на conformance CSV и сравнивает созданный `results.csv` с golden-файлом.
- Kotlin: JUnit вызывает `ScoringEngine.scoreAll()` на тех же данных и сравнивает пять значений для каждой строки.
- Dart: Flutter unit test вызывает `FraudGuardService.analyze()` на копии того же fixture в `dart/assets/data/conformance/` и сравнивает те же поля.

При сравнении `risk_factors` порядок также важен: он должен оставаться `HIGH_AMOUNT/UNUSUAL_AMOUNT`, затем `HIGH_VELOCITY`, затем признаки страны, устройства и категории согласно фактически сработавшим правилам.

## Известная граница

Golden tests проверяют скоринг и профиль, а не идентичность визуального представления GUI. Работа с очередью оператора, экспортом и кнопками проверяется отдельными ручными сценариями. Dart Web не запускает локальный C++ `.exe` из браузера; сравнение выполняется по общему эталонному CSV.
