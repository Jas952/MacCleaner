# MacCleaner Knowledge Base

Актуальная карта проекта MacCleaner. Состояние сверено с рабочим деревом 2026-07-13.

## Проект

- [[Product|Продукт и назначение]]
- [[Architecture|Архитектура]]
- [[Features|Реализованные возможности]]
- [[Decisions|Технические решения]]
- [[Backlog|Задачи и ограничения]]

## Текущее состояние

- Версия приложения: `1.1`, build `3`.
- Платформа: macOS 13+, Swift 5, SwiftUI.
- Основная внешняя зависимость: Sparkle `2.9.4`.
- В проекте 60 Swift-файлов основного target.
- В `SafetyPolicyTests.swift` находится 39 XCTest-тестов.
- Проверка 2026-07-13: `xcodebuild test` завершилась с `TEST SUCCEEDED`.
- Рабочее дерево содержит незакоммиченные изменения v1.1.1; эта база описывает именно их текущее состояние, а не только последний commit.

## Основные области

- Dashboard и menu bar мониторинг
- Процессы и окна
- Температуры и вентиляторы
- Optimize: RAM, мусор, обслуживание, DNS, Safe Delete и Startup
- Storage: приложения, Disk Map, Large Files, Junk, Advisor, Duplicates, Similar Photos, Cloud Reclaim и Complete Analysis
- Desktop Manager и Pake Apps
- AI Agents, AI indexes и библиотека LLM
- Аппаратная диагностика и физическое обслуживание
- Автоматические обновления

## Статус документации

- [x] Зафиксировано назначение продукта
- [x] Описана актуальная архитектура
- [x] Подтверждены реализованные функции
- [x] Зафиксированы ключевые технические решения
- [x] Составлен подтверждённый backlog

## Источники

- `README.md`
- `MacCleaner/MacCleanerApp.swift`
- `MacCleaner/Views/ContentView.swift`
- `MacCleaner/Services/`
- `MacCleaner/Models/`
- `MacCleanerTests/SafetyPolicyTests.swift`
- `docs/v1.1.1-completion-audit.md`
- `docs/maccleaner-v1.1-technical-report.md`

