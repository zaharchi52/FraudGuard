# Чем и как тестируется FraudGuard

В задании указаны **Google Test** для C++ и **JUnit или Kotest** для Kotlin. В проект также добавлены тесты Flutter для дополнительной Dart-версии.

Важно различать тестовый фреймворк и инструмент запуска тестов: Google Test и JUnit содержат механизмы описания тестов и проверки результатов, а CTest и Gradle помогают их обнаружить и запустить.

## 1. Какие инструменты используются

| Язык | Фреймворк | Файлы | Что проверяет |
|---|---|---|---|
| C++ | Google Test | `cpp/tests/engine_tests.cpp` — 18 тестовых случаев (`TEST`) | Медиану, P95, даты, статусы профиля, правила, пороги и риск-скор |
| C++ | Собственные smoke/integration checks + CTest | `cpp/tests/smoke_tests.cpp` | Пакетную обработку, CSV, golden-набор, отчёты и продолжение после ошибочных строк |
| Kotlin | JUnit 5 + `kotlin.test` assertions | 16 методов `@Test` в 4 файлах `kotlin/src/test/kotlin/fraudguard/` | Скоринг, CSV, ручное решение оператора и запись отчётов |
| Dart | `flutter_test` | 13 тестов `test(...)` в двух файлах `dart/test/` | Скоринг, CSV, эталонные результаты и workflow ручной проверки |

### Google Test и CTest — не одно и то же

- **Google Test (GTest)** — C++-фреймворк. В `engine_tests.cpp` используются `TEST`, `EXPECT_EQ`, `ASSERT_TRUE`, `EXPECT_THROW`.
- **CTest** — инструмент CMake, который запускает зарегистрированные тестовые исполняемые файлы и показывает PASS/FAIL.
- `smoke_tests.cpp` — отдельная программа с собственными проверками `check(...)`. Она запускается через CTest, но сама по себе не является Google Test.

В текущем `CMakeLists.txt` Google Test подключается опционально через `find_package(GTest QUIET)`. В логе, который пользователь прислал, было сообщение `Google Test not found`, а CTest выполнил только `fraudguard_smoke_tests` (1/1). Это полезная проверка, но **это ещё не запуск Google Test**.

## 2. Как включить настоящий Google Test на Windows

В `cpp/CMakeLists.txt` предусмотрена опция загрузки Google Test через CMake FetchContent. Для этого нужен доступ к GitHub при первом запуске.

Из корня проекта в PowerShell:

```powershell
cmake -S cpp -B cpp/build -DBUILD_TESTING=ON -DFRAUDGUARD_USE_GTEST=ON -DFRAUDGUARD_FETCH_GTEST=ON
cmake --build cpp/build --config Release
ctest --test-dir cpp/build -C Release --output-on-failure
```

Либо используйте общий скрипт с флагом:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\scripts\run-all-tests.ps1 -FetchGoogleTest
```

При первом запуске CMake скачает Google Test. При последующих запусках исходники зависимости будут использоваться из CMake build-каталога. В CTest появятся отдельные Google Test cases, а также smoke/integration test.

Если компьютер не имеет доступа к GitHub, можно установить Google Test через vcpkg или использовать уже установленный пакет GTest. Без GTest dependency-free smoke test остаётся доступен, но в отчёте нужно честно указать, что Google Test cases не запускались.

### Как выглядит тест в каждом фреймворке

C++ / Google Test:

```cpp
TEST(DecisionTest, ScoreThirtyMeansReview) {
    EXPECT_EQ(decisionForScore(30), "REVIEW");
}
```

Kotlin / JUnit 5:

```kotlin
@Test
fun `score thirty means review`() {
    assertEquals("REVIEW", ScoringEngine.decisionForScore(30))
}
```

Dart / Flutter Test:

```dart
test('score thirty means review', () {
  expect(ScoringEngine.decisionForScore(30), 'REVIEW');
});
```

Во всех трёх примерах тест задаёт входное значение `30`, вызывает функцию решения и проверяет, что фактический ответ равен `REVIEW`.

## 3. Kotlin: почему JUnit, а не Kotest

В исходном задании написано **JUnit / Kotest** — это альтернативы, не требование использовать оба инструмента.

Проект использует **JUnit 5**:
- аннотация `@Test` отмечает тестовый метод;
- `kotlin.test.assertEquals`, `assertTrue`, `assertFalse` и другие функции сравнивают фактический результат с ожидаемым;
- Gradle запускает тесты командой `.\gradlew.bat test`.

Kotest в проект не подключён и для выполнения требования не нужен, поскольку выбран JUnit 5.

Чтобы принудительно выполнить тесты заново и не получить только `UP-TO-DATE`, выполни:

```powershell
cd kotlin
.\gradlew.bat clean test --rerun-tasks
```

Gradle создаёт HTML-отчёт:

```text
kotlin/build/reports/tests/test/index.html
```

## 4. Dart: дополнительное тестирование

Dart-версия не была обязательной частью исходного задания. Для неё применён стандартный для Flutter пакет `flutter_test`:

```powershell
cd dart
flutter analyze
flutter test
```

`flutter analyze` — статический анализ кода, а не unit-тест. `flutter test` запускает тестовые методы `test(...)` и проверяет условия через `expect(...)`.

## 5. Что именно проверяется

Примеры:

| Пример проверки | Что тест делает |
|---|---|
| Медиана | Передаёт список чисел и сравнивает вычисленную медиану с ожидаемой |
| Порог 30 | Проверяет, что 29 даёт `APPROVE`, а 30 — `REVIEW` |
| Порог 60 | Проверяет, что 59 даёт `REVIEW`, а 60 — `BLOCK` |
| HIGH_VELOCITY | Создаёт пять операций в десятиминутном окне и проверяет появление фактора |
| COLD_START | Передаёт пустую историю и проверяет статус профиля и отсутствие профильных штрафов |
| CSV | Передаёт строку с кавычками и запятой, затем проверяет корректный разбор |
| Ручное решение | Одобряет `REVIEW`, затем проверяет, что повторное решение уже невозможно |
| Golden fixture | Прогоняет 15 транзакций и сравнивает ID, балл, решение, факторы и статус профиля с эталонным CSV |

## 6. Чем unit-тест отличается от интеграционного

- **Unit-тест** проверяет одну небольшую функцию или класс отдельно, например расчёт медианы или выбор решения.
- **Интеграционный тест** проверяет несколько частей вместе, например чтение CSV → скоринг → запись отчёта.
- **Golden/conformance test** сравнивает результат реализации с заранее подготовленным эталоном. В нашем проекте один и тот же golden CSV используется для сверки C++, Kotlin и Dart.
- **Ручной приёмочный тест** проверяет действия в окне или браузере: старт, паузу, выбор `REVIEW`, одобрение/отклонение и экспорт.

## 7. Какие результаты нужно приложить к отчёту

1. Вывод CTest, включая Google Test cases, если GTest включён.
2. HTML-отчёт Gradle/JUnit из `kotlin/build/reports/tests/test/`.
3. Вывод `flutter analyze` и `flutter test`.
4. Скриншоты двух интерфейсов и ручной проверки `REVIEW`.
5. Запись о найденном дефекте и повторном успешном тесте, если дефект исправлялся.

Не указывайте Google Test как пройденный, если в CMake было сообщение `Google Test not found`: в таком запуске отработал только smoke/integration test.
