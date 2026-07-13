# Features

## Реализовано

### Мониторинг

- Dashboard: CPU, memory, disks, processes, battery, thermal, network и GPU summary.
- Menu bar monitor с RAM/CPU/temperature и подробным popover.
- Consumer-aware cadence, уменьшающий тяжёлую работу вне активных экранов.
- Processes: агрегированные экземпляры приложений, раскрытие отдельных PID, CPU, memory, disk и time.
- Windows: окна CoreGraphics с привязкой к процессам.
- Disk: mounted volumes, capacity и usage.

### Optimize

- RAM Advisor без автоматического kill и privileged purge.
- Disk Junk для user-space caches, logs, developer- и AI-tool leftovers.
- System Refresh: QuickLook, font cache, Launch Services и другие выбранные maintenance-задачи.
- DNS cache flush.
- Safe Delete с перемещением выбранных файлов в Trash.
- Startup Optimizer с анализом LaunchAgents, reversible disable/restore и защитой Apple/MacCleaner items.
- Professional и Optimization режимы, общий reset при выходе.

### Storage

- Uninstaller с поиском связанных пользовательских файлов.
- Disk Map с навигацией по выбранному root.
- Large Files с режимами Efficient/Thorough и recursive bounded scan.
- Junk Files с общим scan budget и режимами Efficient/Thorough.
- Cleanup Intelligence: история cleanup, категории, recurring paths и derived metrics.
- Cleanup Advisor с ранжированными рекомендациями.
- Exact Duplicates: metadata → sample → SHA-256, hard-link/cloud protection и обязательное сохранение одной копии.
- Similar Photos: локальный Vision-анализ, повторная проверка snapshot перед Trash и обязательное сохранение одного фото.
- Cloud Reclaim: только локальный eviction подтверждённых iCloud-файлов.
- Complete Analysis: последовательный запуск Advisor, Duplicates, Similar Photos и Cloud Reclaim с единым отчётом.
- Сброс завершённых Storage-сценариев при выходе со вкладки.

### Дополнительные инструменты

- Desktop Manager: grid/list/columns/canvas, preview, metadata, rename, move, organization и Trash.
- Pake Apps: создание standalone web apps через внешний `pake` CLI и управление установленными результатами.
- AI Agents: локальные agent processes, Codex/Claude/Gemini profiles, MCP, skills и components.
- AI Indexes: обнаружение локальных index stores.
- LLM Library: модели, фильтры и fit-оценка через `llmfit`.
- Fans: SMC/thermal readings и fan UI при поддержке оборудования.
- Physical Maintenance: screen dim, keyboard lock и combined mode.
- Diagnostics: keyboard, pointer, speakers, storage health, APFS integrity, SSD SMART, thermal power и network.
- Updates: Sparkle, signed appcast, background/manual checks и общий About & Updates overlay.

### UI и качество

- Общий design system, modal overlay, segmented control и контрастные button styles.
- Launch intro и фиксированное desktop window layout.
- 39 safety/policy XCTest-тестов; текущий test run проходит.

## Реализовано с ограничениями

- Disk Map ограничен глубиной и budget и не является полным `du` всего диска.
- Large Files, Junk, Duplicates, Similar Photos и Cloud Reclaim ограничены deadlines/entry limits; Thorough расширяет, но не отменяет пределы.
- Similar Photos использует эвристику Vision; финальный выбор остаётся за пользователем.
- Fan control и sensor coverage различаются между Intel и Apple Silicon.
- Advanced SSD требует `smartctl`; thermal power может требовать admin-доступ.
- Pake Apps и LLM Library не работают без внешних CLI.
- Uninstaller не реализует привилегированное удаление root-owned приложений.
- Обновления готовы на уровне Sparkle/appcast и GitHub Actions; текущая публичная DMG имеет ad-hoc подпись и показывает предупреждение неизвестного разработчика до внедрения Developer ID/notarization.

## Не является текущей функцией

- Установка нового privileged root helper отключена.
- Автоматическое завершение приложений ради очистки RAM отсутствует.
- Необратимый fallback после ошибки Trash отсутствует в мигрированных пользовательских сценариях.
- Полный forensic scan без ограничений не заявлен.

## Связанные материалы

- [[Product]]
- [[Architecture]]
- [[Decisions]]
- [[Backlog]]
