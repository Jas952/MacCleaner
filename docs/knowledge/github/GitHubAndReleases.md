---
name: MacCleaner GitHub and Releases
description: Единые правила GitHub-контента, версий, release notes и публикации MacCleaner.
---

# GitHub и релизы

## Принципы

- GitHub-текст пишется на английском для пользователей продукта, а не как инженерный журнал.
- В релиз попадают только возможности, присутствующие в DMG и прошедшие обязательные проверки.
- Внутренние типы, функции, файлы, приватные API и подробности рефакторинга в release notes не перечисляются.
- Небольшие исправления интерфейса, производительности и совместимости объединяются в один пользовательский пункт.
- Ограничения распространения, новые разрешения и внешние сетевые взаимодействия указываются явно.

## Версионирование

Используется `MAJOR.MINOR.PATCH`:

- `PATCH` — исправления и улучшения существующих возможностей;
- `MINOR` — заметная новая пользовательская возможность;
- `MAJOR` — несовместимое изменение продукта, данных или основного сценария.

Перед релизом одна версия должна быть установлена в app target, helper, `README.md`, `docs/knowledge/Product.md`, `MacCleaner/ReleaseNotes.md`, Git tag и GitHub Release. Заголовок GitHub Release совпадает с tag (`vX.Y.Z`), а первая строка release notes сохраняет формат `# MacCleaner X.Y.Z` для workflow и Sparkle.

## Единый шаблон GitHub Release

`MacCleaner/ReleaseNotes.md` — единственный публикуемый текст релиза. Первая строка обязательна для release workflow и имеет вид `# MacCleaner X.Y.Z`; остальная часть следует шаблону:

```markdown
## What's new

New tools:

- new user-facing capability and the problem it solves.

Other changes:

- visible improvement or compatibility update;
- combined reliability and polish summary.

## Install

1. Download `MacCleaner.dmg` below.
2. Open the DMG and drag MacCleaner to Applications.
3. Open MacCleaner from Applications. If macOS blocks the first launch, allow it in **System Settings → Privacy & Security**.

This build is distributed without Developer ID notarization, so macOS may show an unknown-developer warning on first launch.
```

## Процесс релиза

1. Сопоставить заявленные изменения с фактическим кодом и обновить [[NextRelease]].
2. Обновить marketing version и строго возрастающий build number во всех targets.
3. Запустить XCTest и локальную Release-сборку DMG; проверить bundle version, подпись, структуру DMG и SHA-256.
4. Разделить реализацию, документацию и release metadata на связные коммиты.
5. Отправить ветку, объединить её с `main`, создать и отправить новый неизменяемый tag `vX.Y.Z`.
6. Дождаться release workflow, затем проверить страницу GitHub Release, `MacCleaner.dmg`, appcast и фактический URL загрузки.

Скриншоты интерфейса можно показывать прямо в описании Release через Markdown image links. Для воспроизводимого релиза изображения хранятся в `docs/readme-media/releases/vX.Y.Z/`, а notes ссылаются на immutable tag URL, а не на изменяемую ветку `main`.

Приватный Sparkle EdDSA key хранится только в GitHub Actions secret `SPARKLE_PRIVATE_KEY`. Его нельзя печатать или добавлять в Git. Текущий ad-hoc DMG не заменяет Developer ID signing/notarization.

## Связанные заметки

- [[Product]]
- [[Architecture]]
- [[Features]]
- [[Decisions]]
- [[NextRelease]]
