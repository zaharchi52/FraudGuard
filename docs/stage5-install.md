# Установка обновлений этапа 5

1. Распакуйте `FraudGuard-stage5-patch.zip` в корень уже существующей локальной папки `FraudGuard` и объедините каталоги.
2. Согласитесь на обновление файлов проекта. Не удаляйте `.git` и не заменяйте личный Gradle Wrapper в `kotlin/gradle/wrapper/`.
3. Откройте корневую папку `FraudGuard` в VS Code.
4. Выполните `scripts\run-all-tests.ps1` в PowerShell или выберите задачу `FraudGuard: Run all tests` через `Terminal → Run Task`.
5. Если все автоматические проверки прошли, выполните ручные сценарии из `manual-acceptance-tests.md` в Kotlin Desktop и Dart Web.
6. Сохраните изменения в Git:

```powershell
git status
git add .
git commit -m "test: add cross-language QA and regression coverage"
git push
```

Если какой-либо тест завершился ошибкой, не отмечайте этап 5 выполненным. Скопируйте полный вывод ошибки и передайте его для исправления; дефект заведите в `defect-report.md`.
