# MacCleaner Knowledge Base

Актуальная карта проекта MacCleaner. Состояние сверено с рабочим деревом 2026-07-18.

## Проект

- [[Product|Продукт и назначение]]
- [[Architecture|Архитектура]]
- [[Features|Реализованные возможности]]
- [[Decisions|Технические решения]]
- [[Opportunities|Единый план улучшений и задач]]

## Текущее состояние

- Версия приложения: `1.0.6`, build `8`.
- Платформа: macOS 13+, Swift 5, SwiftUI.
- Основная внешняя зависимость: Sparkle `2.9.4`.
- В проекте 59 Swift-файлов основного target.
- В `SafetyPolicyTests.swift` находится 50 XCTest-тестов.
- Проверка 2026-07-18: `xcodebuild test` завершилась с `TEST SUCCEEDED`.
- База знаний описывает текущую версию 1.0.6 и фактическое состояние рабочего дерева.

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
- [x] Составлен единый реестр улучшений и задач

## Источники

- `README.md`
- `MacCleaner/MacCleanerApp.swift`
- `MacCleaner/Views/ContentView.swift`
- `MacCleaner/Services/`
- `MacCleaner/Models/`
- `MacCleanerTests/SafetyPolicyTests.swift`
- `docs/effectiveness-measurement-report.md`
- `docs/maximum-effectiveness-and-memory-compression-report.md`
- `docs/thermal-load-notification-analysis.md`
- `docs/background-suspension-analysis.md`
