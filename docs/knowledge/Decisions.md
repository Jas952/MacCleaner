# Decisions

## Нативное macOS-приложение

Статус: принято

Решение: SwiftUI является основным UI-слоем; AppKit, CoreGraphics, IOKit, AVFoundation и Vision используются точечно для системных возможностей.

Обоснование: продукт тесно интегрирован с macOS и должен получать локальные системные данные без отдельного backend.

Связанные файлы: `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Views/`, `MacCleaner/Services/`.

## Долгоживущие feature services

Статус: принято

Решение: тяжёлые Storage-сервисы принадлежат корневому `ContentView`; `StorageWorkspaceService` агрегирует специализированные анализаторы.

Обоснование: повторное создание service/view graph при навигации вызывало лишнюю работу и потерю состояния.

Последствия: Storage можно prewarm; завершённое состояние сбрасывается при выходе, активная операция сохраняется.

Связанные файлы: `MacCleaner/Views/ContentView.swift`, `MacCleaner/Services/StorageWorkspaceService.swift`.

## Trash-only для пользовательских удалений

Статус: принято

Решение: все мигрированные destructive flows используют `SafeDeletionService` и не переходят к permanent delete после ошибки Trash.

Обоснование: неудача обратимой операции не должна неожиданно становиться необратимым удалением.

Последствия: операция может завершиться ошибкой и потребовать участия пользователя; это сознательная safety-цена.

Связанные файлы: `MacCleaner/Services/SafeDeletionService.swift`, Storage/Optimize/Desktop services.

## Bounded scanners

Статус: принято

Решение: файловые анализаторы имеют общие entry/time budgets, cancellation и режимы Efficient/Thorough.

Обоснование: неограниченный обход home или диска блокирует UI и создаёт неконтролируемый I/O.

Последствия: результат может быть ограниченным; интерфейс и документация не должны называть его полным forensic scan.

Связанные файлы: `MacCleaner/Services/ScanResourceBudget.swift`, `StorageAnalyzerService.swift`, `DuplicateFinderService.swift`, `SimilarPhotoService.swift`, `CloudReclaimService.swift`.

## Поэтапная проверка дубликатов

Статус: принято

Решение: сначала группировать metadata, затем использовать quick fingerprint и только после этого полный SHA-256.

Обоснование: полный hash каждого файла слишком дорог; удаление требует доказательства полного совпадения.

Последствия: hard links и cloud placeholders исключаются; перед Trash fingerprint проверяется повторно.

Связанный файл: `MacCleaner/Services/DuplicateFinderService.swift`.

## Локальный анализ фотографий

Статус: принято

Решение: использовать ImageIO и Vision без отправки изображений в сеть; ничего не выбирать автоматически после первого скана.

Обоснование: приватность и риск ложного совпадения важнее полностью автоматической очистки.

Связанный файл: `MacCleaner/Services/SimilarPhotoService.swift`.

## Cloud Reclaim не удаляет cloud-файл

Статус: принято

Решение: вызывать `evictUbiquitousItem` только для current, uploaded и conflict-free ubiquitous items.

Обоснование: цель — освободить локальное место, сохранив облачную копию.

Связанный файл: `MacCleaner/Services/CloudReclaimService.swift`.

## RAM Cleaner без purge и automatic kill

Статус: принято

Решение: показывать давление памяти и рекомендации, но не завершать приложения и не запускать privileged `purge` автоматически.

Обоснование: macOS сама управляет inactive/compressed memory; искусственное освобождение Free RAM может ухудшить работу и привести к потере данных.

Связанные файлы: `MacCleaner/Services/CleanerService.swift`, `MacCleaner/Views/CleanerView.swift`.

## Retire legacy root helper

Статус: принято

Решение: старый daemon source оставлен только в некомпилируемом `#if false`; новый `HelperManager` умеет только обнаружить и удалить прежнюю установку.

Обоснование: legacy daemon принимал unauthenticated HTTP-команды на localhost с root-правами.

Последствия: функции используют user-scoped APIs; старый helper можно удалить с подтверждением администратора.

Связанный файл: `MacCleaner/Services/SystemMonitor.swift`.

## Consumer-aware мониторинг

Статус: принято

Решение: cadence `SystemMonitor` зависит от активных экранов.

Обоснование: process snapshots, sensors и `system_profiler` не должны работать с одинаковой частотой, когда их никто не отображает.

Связанный файл: `MacCleaner/Services/SystemMonitor.swift`.

## Sparkle для обновлений

Статус: принято

Решение: использовать Sparkle 2.9.4, HTTPS appcast, EdDSA подпись и шестичасовой интервал автоматических проверок.

Обоснование: приложению нужен проверяемый канал доставки исправлений.

Последствия: увеличивается bundle; текущая GitHub DMG распространяется с ad-hoc подписью и предупреждением неизвестного разработчика. Developer ID signing и notarization остаются отдельным улучшением распространения.

Release Notes хранятся в единственном файле `MacCleaner/ReleaseNotes.md`, который использует UI и release workflow.

Связанные файлы: `MacCleaner/Services/UpdateService.swift`, `MacCleaner/Info.plist`, `MacCleaner/ReleaseNotes.md`, `.github/workflows/release.yml`, `MacCleaner.xcodeproj/project.pbxproj`.

## Связанные материалы

- [[Architecture]]
- [[Features]]
- [[Backlog]]
