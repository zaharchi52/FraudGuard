# C++17: сборка и запуск

## Требования

- компилятор с поддержкой C++17 (GCC, Clang или MSVC);
- CMake 3.16 или новее.
- Google Test необязателен: если он найден в системе, CMake собирает полный набор unit-тестов. Если не найден, запускается небольшой автономный набор smoke-тестов.

## Сборка из корня проекта

```bash
cmake -S cpp -B cpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build cpp/build --config Release
ctest --test-dir cpp/build --output-on-failure
```

Исполняемый файл обычно будет `cpp/build/fraudguard` на Linux/macOS или `cpp\build\fraudguard.exe` при сборке MinGW в Windows. При генераторе Visual Studio он может находиться в `cpp/build/Release/fraudguard.exe`.

## Запуск на эталонных данных

Из корня репозитория:

```bash
./cpp/build/fraudguard --transactions data/transactions.csv --history data/history.csv --out-dir reports
```

В Windows PowerShell замените путь к исполняемому файлу на фактический, например:

```powershell
.\cpp\build\fraudguard.exe --transactions data/transactions.csv --history data/history.csv --out-dir reports
```

Аргументы:

- `--transactions FILE` — обязательный CSV новых транзакций;
- `--history FILE` — CSV истории (по умолчанию `data/history.csv`);
- `--no-history` — запустить без истории;
- `--out-dir DIR` — каталог отчётов (по умолчанию `reports`);
- `--help` — справка.

После успешного запуска появятся:

- `reports/results.csv` — все валидные скорированные транзакции;
- `reports/alerts.csv` — только `REVIEW` и `BLOCK`;
- `reports/errors.csv` — строки/файлы, которые не удалось обработать.

Невалидная отдельная строка не останавливает пакет. Ошибка чтения или схема основного файла транзакций приводит к ненулевому коду завершения. Отсутствие файла истории включает режим без профилей и выводит предупреждение.

## Проверка входных данных

```bash
./cpp/build/fraudguard --transactions data/transactions_invalid.csv --history data/history.csv --out-dir reports-invalid
```

В текущем наборе три ошибки будут записаны в `reports-invalid/errors.csv`, а валидная строка `T9004` всё равно будет обработана.
