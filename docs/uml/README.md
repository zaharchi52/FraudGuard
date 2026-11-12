# UML-диаграммы FraudGuard

Исходники диаграмм сделаны в формате PlantUML:

- `use-case.puml` — пользовательские сценарии и акторы;
- `class-diagram.puml` — модель данных, ключевые компоненты и связи;
- `sequence.puml` — последовательность пакетной обработки.

## Как просмотреть диаграммы

1. Откройте один из `.puml` файлов в редакторе с поддержкой PlantUML (например, VS Code с расширением PlantUML) либо в веб-редакторе PlantUML.
2. Выполните Preview / Render.
3. Для отчёта экспортируйте диаграмму в SVG или PNG; исходник `.puml` сохраните в репозитории.

При редактировании сверяйтесь с `../requirements.md`: правила, статусы профиля, пороги и выходные файлы должны совпадать.

## Дополнительные диаграммы этапа 4

- [`kotlin-class-diagram.puml`](kotlin-class-diagram.puml) — классы Kotlin-порта, GUI, сервисов и отчётов.
- [`kotlin-live-sequence.puml`](kotlin-live-sequence.puml) — загрузка CSV, скоринг, имитация ленты и принятие решения оператором.
<<<<<<< HEAD

- [`dart-class-diagram.puml`](dart-class-diagram.puml) — классы Dart-реализации и Flutter Web UI.
- [`dart-live-sequence.puml`](dart-live-sequence.puml) — загрузка файлов, симуляция потока, ручное решение и экспорт CSV в браузере.
=======
>>>>>>> 1d3001cacd41e209267ec19f5bcb4072cd6626dd
