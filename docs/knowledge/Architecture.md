# Architecture

## Обзор

MacCleaner — монолитное нативное macOS-приложение на SwiftUI. UI, доменные сервисы и модели собираются в один app target; отдельный test target проверяет safety- и policy-контракты. Основное разделение проходит по каталогам `Views`, `Services`, `Models` и `Settings`.

Репозиторий также содержит независимый статический промо-сайт в `website/`. Он не входит в app target, не имеет runtime-зависимостей и использует HTML, CSS и небольшой vanilla JavaScript. Первый экран состоит из двух последовательно анимируемых физических состояний MacBook с общей геометрией и точкой шарнира: фронтальная внешняя крышка с защитным знаком сначала полностью складывается в тонкую линию, после чего без временного наложения проявляется корпус с ограниченной по перспективе клавиатурной декой и раскрывающимся назад display lid. После раскрытия виден macOS desktop с menu bar, Dock и обычным окном MacCleaner.

Интерактив не воспроизводит интерфейс HTML-компонентами, а по порядку переключает 11 системных снимков основных sidebar-разделов: Dashboard, Processes, Fans / Cooling, Disk, Optimize, Storage, Desktop, Pake Apps, Agents, Library и Tools. Системные захваты окна нормализованы до `2600 × 1576`, не содержат указателя мыши и отображаются без изменения пропорций. Внешние стрелки, горизонтальный tablist и прозрачные hotspot-кнопки над реальной боковой панелью используют один контроллер переключения. Нижняя продуктовая часть не дублирует gallery: отдельные композиции раскрывают системный обзор, AI Agents и maintenance/diagnostics, а остальные направления представлены текстовой feature band.

```mermaid
flowchart LR
    App[MacCleanerApp] --> Root[ContentView]
    App --> Menu[AppKit NSStatusItem]
    Menu --> Popover[SwiftUI MenuBarPopover]
    Root --> Views[Feature Views]
    Root --> Monitor[SystemMonitor]
    Views --> Services[Domain Services]
    Services --> Models[Models]
    Services --> OS[macOS APIs and file system]
    Services --> CLI[External CLI]
    Services --> Safety[SafeDeletionService]
    Update[UpdateService] --> Sparkle[Sparkle]
```

## Точки входа

- `MacCleaner/MacCleanerApp.swift` содержит `@main MacCleanerApp`.
- Главное окно имеет фиксированный content size 1300×760 и открывает `ContentView`.
- AppKit `NSStatusItem` показывает компактный мониторинг через общий `SystemMonitor`, а его popover остаётся SwiftUI-представлением.
- `Settings` открывает `SettingsView` и управляет составом, drag-порядком, стилем и форматом модулей menu bar.
- Первая вкладка Settings также показывает статическую companion-карточку Browser Monitor: локальный asset, ссылки на репозиторий и ZIP релиза и popover-инструкцию установки. MacCleaner не загружает и не устанавливает расширение самостоятельно.
- `AppDelegate` сохраняет приложение после закрытия последнего окна и корректно завершает активные maintenance-режимы.
- Sparkle-команда проверки обновлений добавлена в меню приложения.

## Навигация и состояние

`MacCleaner/Views/ContentView.swift` владеет корневой навигацией `Tab` и долгоживущими сервисами функций.

Основные вкладки: Dashboard, About, Processes, Fans, Optimize, Windows, Disk, Storage, Desktop, Pake Apps, Agents, Indexes, Library и Utilities. В sidebar напрямую показывается подмножество; About доступен через нижний hardware block, а Indexes входит в AI-область.

Корневые `@StateObject`:

- `UninstallerService`
- `StorageAnalyzerService`
- `StorageWorkspaceService`
- `DesktopService`
- `CleanerViewState`
- `PakePackager`
- `UpdateService.shared`
- `AppModalCoordinator`

Storage предварительно создаётся один раз и сохраняется в стабильной hierarchy. При переключении вкладки состояние завершённой операции сбрасывается, но активная операция не прерывается неявно.

## Общая телеметрия

`MacCleaner/Services/SystemMonitor.swift` публикует память, CPU, диски, процессы, окна, вентиляторы, температуры, батарею, сеть и GPU. Cadence зависит от активных consumers: специализированные экраны получают более свежие данные, а idle-режим уменьшает число тяжёлых snapshot и `system_profiler` запусков.

Источники данных включают Mach APIs, IOKit, IORegistry, CoreGraphics, `getifaddrs`, mounted volume resource values и ограниченные shell-команды.

## Доменные сервисы

### Storage

- `StorageAnalyzerService.swift` — Disk Map, Large Files, Junk, cleanup history и статистика.
- `StorageWorkspaceService.swift` — общий lifecycle Advisor, Duplicates, Similar Photos и Cloud Reclaim.
- `CleanupAdvisorService.swift` — ранжированные рекомендации по размеру, риску и стоимости восстановления.
- `DuplicateFinderService.swift` — metadata grouping, quick fingerprint и полный SHA-256.
- `SimilarPhotoService.swift` — локальные ImageIO/Vision fingerprints.
- `CloudReclaimService.swift` — проверка ubiquitous metadata и локальный eviction.
- `UninstallerService.swift` — приложения и связанные пользовательские файлы.
- `ScanResourceBudget.swift` — общие entry/deadline limits.

### Optimize и процессы

- `CleanerService.swift` — анализ RAM, disk junk, DNS и system refresh.
- `StartupOptimizerService.swift` — LaunchAgents, reversible disable/restore и runtime impact.
- `ProcessTreeService.swift` — process snapshot, агрегация экземпляров, SIGTERM/SIGKILL по явному действию.
- `ProcessDetailService.swift` — подробности выбранного процесса.
- `SafeDeletionService.swift` — единая path policy и Trash-only удаление.

### Прочие области

- `DesktopService.swift` — Desktop/current folder, сортировка, перемещение, rename, preview и Trash.
- `AIWorkloadService.swift` — процессы AI-инструментов, профили агентов, MCP и skills.
- `AIIndexStoreService.swift` — локальные AI/index stores.
- `LLMFitService.swift` — библиотека и оценка моделей через `llmfit`.
- `SMCService.swift` — SMC/fan/thermal данные с hardware-dependent fallback.
- `MaintenanceService.swift` — screen dim, keyboard lock и объединённый режим.
- `HardwareDiagnosticServices.swift` — speaker, storage health, APFS, SSD, thermal power и network.
- `KeyboardDiagnosticService.swift` — события клавиатуры и диагностическая сессия.
- `UpdateService.swift` — адаптер состояния поверх Sparkle.

## UI-инфраструктура

`MacCleaner/Views/DesignSystem.swift` содержит semantic colors, typography, графики, button styles, `AppSegmentedControl`, footer и общий `AppModalOverlay`. `AppModalCoordinator` централизует информационные и feature overlays.

### Модульные Tools и menu bar

`UtilityToolID` является единым каталогом инструментов. `SettingsManager` сохраняет выбранный пользователем набор Tools, быстрые menu bar actions, состав, drag-порядок, индивидуальный формат и индивидуальный стиль `Battery / Values` каждого telemetry gauge. Настройка Tools содержит один переключатель присутствия для готового инструмента; Media Compressor, App Audio Report и Charge Limit остаются видимыми там как `BETA / In development`, но не могут попасть в рабочий sidebar. Быстрый доступ настраивается отдельно во вкладке Menu Bar. `UtilityToolsView` строит постоянную левую source-list навигацию только из включённых готовых инструментов; первый пункт всегда открывает вводный экран с локальной SwiftUI-анимацией, учитывающей Reduce Motion. Все detail-экраны используют общий header и содержательные panels, высота которых определяется реальным содержимым без искусственных spacer-разрывов.

Системная логика новых инструментов вынесена в `UtilityToolServices.swift` и `ClipboardHistoryService.swift`. Floating Shelf и Clipboard History принадлежат самостоятельным nonactivating `NSPanel`, поэтому `⌥S` и `⌥C` показывают только нужную utility-панель, не открывая и не поднимая главное окно. Hotkeys регистрируются при запуске процесса, а не при появлении SwiftUI-сцены; они продолжают работать, пока MacCleaner запущен в menu bar или фоне. Узкий `NSViewRepresentable` меняет уровень Shelf между `.floating` и `.normal`; закрепление хранится локально и по умолчанию включено. Carbon использует физические key codes, поэтому команды не зависят от английской/русской раскладки и не требуют глобального чтения клавиатуры.

Команды Shelf в Tools представлены общим `SubtleToolIconButton`: нейтральная icon-only поверхность усиливается только при hover, а название действия сохранено в tooltip и accessibility label. Действия верхних Shelf/Clipboard-карточек находятся непосредственно после их заголовков и используют компактный размер. Парная высота определяется через SwiftUI preference как максимум естественных высот обеих карточек, поэтому они совпадают без жёсткой константы и адаптируются к шрифту и содержимому. Pin toggle использует `MutedSwitchStyle`: компактную нейтральную capsule без зависимости от яркого system accent color.

`ClipboardHistoryService` опрашивает только `NSPasteboard.changeCount`, хранит до 12 уникальных session-only элементов и поддерживает текст, изображения и file URLs. Для каждой записи `PasteboardPayload` материализует все доступные representations исходных pasteboard items и восстанавливает их вместе: plain text, RTF/HTML, image types, file URLs и дополнительные форматы источника не сводятся к одному preview-типу. Тот же payload создаёт `NSItemProvider` для добавления текущего clipboard в Shelf, поэтому последующий drag-out сохраняет набор форматов. Компактный borderless `NSPanel` использует системный `NSVisualEffectView` с material `.popover` и blending `.behindWindow`, поэтому фон остаётся бесцветным, полупрозрачным и адаптивным к теме macOS. Видимых action-кнопок нет: при открытии выделяется самая свежая запись, стрелки меняют выделение и прокручивают список, Enter восстанавливает выбранное, двойной клик делает то же мышью, очистка доступна из контекстного меню, а `⌘1–4` возвращает первые четыре элемента в pasteboard. Панель закрывается при клике вне или после восстановления; данные не записываются на диск.

Menu bar использует существующий `SystemMonitor`, поэтому включение CPU/RAM/GPU/temperature/battery gauges не создаёт параллельный sampler. `StatusBarController` владеет AppKit `NSStatusItem`; каждый модуль независимо выбирает `Battery` или `Values`. `Battery` показывает подписанный вертикальный indicator: заполнение снизу вверх передаёт нагрузку/нагрев, semantic green/orange/red — severity, temperature сохраняет термометр, а compact marker (`%/C`, `%/G`, `%/°`, `C/F`, `%/clock`) обозначает формат и использует тот же semantic color. `Values` выводит рядом с `CPU`, `RAM`, `GPU`, `TEMP`, `BAT` фактическое процентное или числовое значение. Точные values остаются в accessibility label, tooltip и SwiftUI `MenuBarPopover`. Settings хранит состав, порядок, формат и стиль каждого gauge; прежний общий style автоматически мигрирует во все индивидуальные записи. В UI глобального блока `Display style` нет: обе пары настроек находятся в строке модуля как icon-only segmented controls с tooltip и accessibility label. Включённые строки являются draggable tiles, а выключенные остаются ниже как неактивные плитки. Когда все gauges выключены, status item показывает bundle icon MacCleaner.

Обычный клик по `NSStatusItem` показывает transient popover без `NSApp.activate`, поэтому существующее главное окно не поднимается поверх текущего приложения. Пока popover видим, `StatusBarController` держит временный global mouse monitor: внешний клик закрывает меню, а monitor удаляется через `NSPopoverDelegate` сразу после закрытия. Активация сохраняется только у явных действий `Open MacCleaner` и `Settings…`.

Визуально каждый menu bar gauge собран в центрированную группу: short label + vertical battery + marker либо short label + monospaced direct value. Группы разделены тонкими semantic dividers. Для AppKit image attachments задаётся явный baseline offset, чтобы 16-point battery не поднимала и не опускала соседний текст. Temperature добавляет термометр только в battery-композиции; числовой режим уже содержит единицу измерения. Settings preview использует тот же выбранный стиль.

Media Compressor, App Audio Report и Charge Limit временно исключены из runtime-каталога и обозначены beta только в Settings. Их код не считается доступной пользовательской функцией до отдельного возвращения. Screen Text и Awake Profiles также отсутствуют в runtime-каталоге.

## Безопасность

`SafeDeletionService` нормализует путь, проверяет границы директорий, защищает app и рабочие данные MacCleaner и вызывает `FileManager.trashItem`. Permanent-delete fallback в мигрированных пользовательских flows отсутствует.

Legacy root daemon сохранён в `SystemMonitor.swift` только внутри `#if false`; текущий `HelperManager` умеет обнаружить и удалить старую установку, но не устанавливает и не вызывает daemon.

Приложение не sandboxed. Entitlements разрешают Apple Events, user-selected read/write и отключение library validation для runtime-зависимостей.

### Owner-группировка Junk Files

`StorageAnalyzerService` сохраняет developer- и AI-данные внутри существующего `Junk Files`, но выдаёт их отдельными стабильными owner-группами. Группы включают Xcode (DerivedData, Archives, Device Support, Simulator data/runtime), SwiftPM, CocoaPods, Carthage, Homebrew, npm/Yarn/pnpm, Python pip/uv, Gradle/Maven, Cargo, Go, JetBrains, VS Code/Cursor/Claude caches и обнаруженные артефакты проектов.

Каждая группа содержит объяснение, размер, тип последствий (`rebuild`, `redownload`, `review`, `protected`) и, для проектных артефактов, путь проекта. Для Git-проектов выполняется локальный `git status --porcelain`; незакоммиченные изменения не блокируют сам анализ, но требуют отдельного подтверждения перед Trash. AI-модели, Hugging Face storage и Docker Desktop data отмечены как protected и не удаляются массовым действием.

В результатах сканирования группа раскрывается в плоское дерево `категория → элементы`. Для каждого элемента показываются имя, полный путь и размер. Если корень содержит больше 12 дочерних элементов, оставшиеся мелкие файлы объединяются в одну строку-папку с количеством элементов и суммарным размером. Категории с последствиями `safe`, `rebuild` или `redownload` автоматически отмечаются для очистки; `review` и `protected` остаются снятыми.

Открытые поддерживаемые браузеры обнаруживаются через `NSWorkspace`. Перед очисткой браузерных кэшей приложение просит подтверждение и отправляет обычный terminate-запрос; принудительное завершение не используется. Все реальные удаления по-прежнему проходят через `SafeDeletionService` и Trash.

Large Files сначала использует обычный пользовательский `FileManager.trashItem`. Если конкретные выбранные файлы отклонены macOS по правам доступа, пользователь может отдельно подтвердить системный запрос администратора; повторная операция адресно перемещает только эти файлы в текущую пользовательскую корзину через `/usr/bin/osascript`. Пароль не передаётся приложению и не сохраняется.

## Обновления и зависимости

- Sparkle `2.9.4` подключён через SwiftPM.
- Appcast передаётся по HTTPS и подписывается EdDSA.
- Автоматическая проверка настроена на 6 часов и полностью принадлежит планировщику Sparkle; `ContentView` не запускает дополнительные фоновые сессии при появлении окна.
- Пользовательская команда вызывает foreground `checkForUpdates()`, поэтому стандартный Sparkle user driver показывает Download → Install → Relaunch и поднимает уже найденное или скачанное обновление. Включённый automatic mode одновременно разрешает проверки и фоновую загрузку; готовое обновление устанавливается Sparkle при выходе либо после подтверждённого перезапуска.
- `MacCleaner/ReleaseNotes.md` является единым источником текста для окна Updates, GitHub Release и appcast.
- Внешние `pake`, `llmfit`, `smartctl` и `powermetrics` доступны только при наличии в системе и соответствующих прав.
- Промо-сайт не требует сборщика или JavaScript-фреймворка и может публиковаться как обычный набор статических файлов из `website/`.

## Тесты

`MacCleanerTests/SafetyPolicyTests.swift` содержит 50 XCTest-тестов. Они проверяют path boundaries, защиту данных MacCleaner, Trash semantics и исчезновение временного файла между сканированием и очисткой, scan budgets, cleanup ranking, exact duplicates, similar photos, cloud reclaim, startup items, process aggregation, RAM policy, reset-контракты, глубокий Large Files scan, запрет сохранения увеличившегося результата Media Compressor, исключение beta-инструментов из workspace, компактные форматы, два стиля menu bar gauges, сохранение выбранного стиля и drag-порядка, а также полный pasteboard representation round-trip.

Проверка 2026-07-18:

```text
xcodebuild test -project MacCleaner.xcodeproj -scheme MacCleaner \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
TEST SUCCEEDED
```

## Связанные материалы

- [[Product]]
- [[Features]]
- [[Decisions]]
- [[Opportunities]]
