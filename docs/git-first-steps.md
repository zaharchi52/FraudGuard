# Первые шаги Git

Эти команды выполняются из терминала в папке `FraudGuard/`. Нужен установленный Git и созданный пустой репозиторий на GitHub или GitLab.

## 1. Первый локальный коммит

```bash
git init
git branch -M main
git add .
git commit -m "chore: initialize FraudGuard requirements and sample data"
```

## 2. Подключение удалённого репозитория

Скопировать URL своего пустого репозитория с GitHub/GitLab и выполнить (замените URL на свой):

```bash
git remote add origin <URL_ВАШЕГО_РЕПОЗИТОРИЯ>
git push -u origin main
```

Не вставляйте пароль или токен доступа в исходники или README. Авторизацию Git выполняйте безопасным способом, предложенным выбранным сервисом.

## 3. Работа через ветку и Pull Request

Пример ветки для этапа требований:

```bash
git switch -c docs/requirements
# внести изменения в документы
git add docs/ VISION.md
git commit -m "docs: define FraudGuard requirements"
git push -u origin docs/requirements
```

После отправки ветки создать Pull Request (GitHub) или Merge Request (GitLab) в `main`, описать изменения и проверить diff. Для трёх участников используйте отдельные ветки, а перед началом работы обновляйте локальную ветку:

```bash
git switch main
git pull --ff-only
```

Для учебного проекта достаточно веток по задачам и PR; необязательно заводить `develop`, если это усложняет процесс.
