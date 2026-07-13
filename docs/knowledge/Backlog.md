# Backlog

## Подтверждённые задачи

### Безопасность и распространение

- [ ] Удалить мёртвый legacy daemon source из `SystemMonitor.swift` после завершения периода миграции; текущий код отключён через `#if false`.
- [ ] Проверить необходимость entitlement `com.apple.security.cs.disable-library-validation` и сузить его, если Sparkle-конфигурация позволяет.
- [ ] Настроить Developer ID signing и notarization для публичной DMG.
- [ ] Зафиксировать и проверить release-процесс хранения Sparkle private signing key.
- [ ] Привязать `pake`, `llmfit`, `smartctl` и другие внешние CLI к проверяемому источнику/версии либо явно показывать происхождение бинарника.

### Производительность

- [ ] Профилировать launch, menu bar и переход в Storage через Instruments.
- [ ] Сократить рост bundle и RSS, не откатывая safety-функции и Sparkle.
- [ ] Рассмотреть lazy loading крупных feature modules и сервисов, которые не нужны при запуске.
- [ ] Измерить интерактивный переход в Storage frame-by-frame, а не только общий runtime startup.

### Функциональные ограничения

- [ ] Решить, нужен ли поддерживаемый сценарий удаления root-owned приложений; сейчас Uninstaller их пропускает.
- [ ] Улучшать sensor/fan coverage на Apple Silicon только при наличии надёжного системного API.
- [ ] Явно документировать зависимость Advanced SSD от `smartctl` и Thermal Power от admin-доступа в пользовательском интерфейсе.
- [ ] Продолжить калибровку Similar Photos на реальных наборах, сохраняя обязательное пользовательское подтверждение.
- [ ] Проверить, нужны ли отдельные Junk-категории для browser cache, DMG и screenshots вместо текущей общей классификации.

### Тестирование

- [ ] Добавить тестируемый adapter для state machine `UpdateService` и покрыть idle/checking/success/available/failure.
- [ ] Добавить UI-тесты ключевых destructive confirmation flows.
- [ ] Добавить регрессионные тесты для legacy helper cleanup без реального изменения `/Library`.
- [ ] Сохранить 39 текущих safety/policy тестов обязательным CI gate.
- [ ] Повторить light/dark и minimum-window визуальную ревизию перед следующим release.

## Завершено в текущем рабочем дереве

- [x] Заполнена база знаний Obsidian по фактическому коду.
- [x] Введена единая Trash-only policy.
- [x] Добавлены bounded Efficient/Thorough scanners.
- [x] Добавлены Cleanup Advisor, Exact Duplicates, Similar Photos и Cloud Reclaim.
- [x] Добавлен Complete Analysis с последовательным выполнением.
- [x] Реализованы reset-контракты Optimize и Storage.
- [x] Реализована агрегация процессов с отдельными PID.
- [x] Legacy root helper отключён и заменён cleanup-only manager.
- [x] Текущие 39 XCTest-тестов проходят 2026-07-13.

## Связанные материалы

- [[Product]]
- [[Architecture]]
- [[Features]]
- [[Decisions]]
