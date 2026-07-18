# Decisions

## Нативное macOS-приложение

Статус: принято

Решение: SwiftUI является основным UI-слоем; AppKit, CoreGraphics, IOKit, AVFoundation и Vision используются точечно для системных возможностей.

Обоснование: продукт тесно интегрирован с macOS и должен получать локальные системные данные без отдельного backend.

Связанные файлы: `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Views/`, `MacCleaner/Services/`.

## Единый каталог включаемых инструментов

Статус: принято

Решение: доступность Tools, быстрых menu bar actions и menu bar gauges хранится в `SettingsManager`, а метаданные инструментов — в `UtilityToolID`. Tools использует левую selection-driven навигацию; Settings остаётся отдельным системным окном.

Обоснование: большой фиксированный набор горизонтальных переключателей перестал масштабироваться. Единый каталог исключает расхождение между основным окном, Settings и menu bar и позволяет пользователю не загружать интерфейс ненужными функциями.

Последствия: выключенный инструмент исчезает из Tools и быстрого доступа, но его локальные настройки не удаляются. Вводный пункт остаётся всегда. Media Compressor, App Audio Report и Charge Limit помечены `BETA / In development` без переключателя и не попадают в workspace даже при наличии старого persisted ID.

Связанные файлы: `MacCleaner/Models/UtilityTool.swift`, `MacCleaner/Settings/SettingsManager.swift`, `MacCleaner/Views/UtilityToolsView.swift`.

## AppKit status item для модульного menu bar

Статус: принято

Решение: фактический элемент системной строки создаётся через AppKit `NSStatusItem`, а содержимое popover остаётся на SwiftUI. `StatusBarController` собирает каждый модуль в его собственном сохранённом стиле. `Battery` использует подписанный вертикальный gauge image: заполнение снизу вверх отражает load/heat, semantic color — severity, а compact marker (`%/C`, `%/G`, `%/°`, `C/F`, `%/clock`) делает выбранный формат видимым. `Values` выводит рядом с той же короткой подписью непосредственное процентное или числовое значение monospaced шрифтом. Тонкие системные разделители отделяют модули; AppKit attachments имеют явный baseline offset. Settings не содержит отдельного глобального `Display style`: style и format выбираются icon-only segmented controls непосредственно в каждой строке, а прежнее глобальное значение мигрирует на все gauges. Порядок включённых модулей меняется pointer-drag и сохраняется в `SettingsManager`. Если пользователь отключил все gauges, status item использует bundle icon приложения через `NSApplication.applicationIconImage`.

Обоснование: SwiftUI `MenuBarExtra` обрезал динамическую составную подпись до первого модуля, хотя preview настроек показывал все модули. AppKit-мост сохраняет нативное поведение и даёт предсказуемый контроль реальной ширины status item.

Последствия: контроллер наблюдает общий `SystemMonitor` и `SettingsManager`, поэтому отдельный sampler не создаётся. Сам клик по status item показывает transient popover без активации приложения и не поднимает главное окно. Для закрытия по клику в другом приложении используется временный глобальный mouse monitor, который не перехватывает события и удаляется делегатом сразу после закрытия popover. Открытие главного окна, Shelf и Settings передаётся в SwiftUI popover отдельными явными действиями; только действия, которым действительно нужно окно приложения, вызывают его активацию.

Связанные файлы: `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Settings/SettingsView.swift`.

## Capability-gated системные инструменты

Статус: принято

Решение: Media Compressor, per-app audio и Charge Limit временно не являются доступными Tools. Они остаются в каталоге Settings как beta-задел без переключателя. До отдельного продуктового возврата существующие реализации не заявляются как пользовательская возможность.

Обоснование: восстановление аудиомаршрута и управление зарядом являются hardware/OS-dependent операциями с риском системного побочного эффекта.

Последствия: Screen Text и Awake Profiles удалены из пользовательского каталога; Media Compressor, App Audio Report и Charge Limit видны только как `In development`.

Связанные файлы: `MacCleaner/Views/UtilityToolsView.swift`, `MacCleaner/Services/UtilityToolServices.swift`, `docs/utility-tools-and-menu-bar-analysis.md`.

## Session-only clipboard и глобальные utility hotkeys

Статус: принято

Решение: Clipboard History хранит максимум 12 уникальных элементов только в памяти процесса и наблюдает `NSPasteboard.changeCount`. `⌥C` и `⌥S` регистрируются при запуске процесса через Carbon по физическим key codes; это даёт одинаковое поведение для английской и русской раскладок без глобального перехвата всех нажатий. Clipboard History и Drop Shelf показываются самостоятельными nonactivating `NSPanel`, не активируют главное окно и доступны, пока MacCleaner работает в menu bar или фоне. История использует системный `NSVisualEffectView` (`.popover`, `.behindWindow`) без фиксированной цветовой заливки и видимых action-кнопок. Floating level Drop Shelf меняется узким `NSViewRepresentable`-мостом.

Обоснование: SwiftUI scene API не даёт одновременно глобальные layout-independent hotkeys, borderless transient panel с keyboard routing и управляемый `NSWindow.Level`. AppKit используется только на этой границе; данные и выбор остаются SwiftUI/ObservableObject.

Последствия: clipboard не персистится и очищается при завершении MacCleaner. История материализует все доступные representations каждого `NSPasteboardItem`; восстановление и Shelf drag-out сохраняют исходный набор форматов, а не только preview text/image/file URL. History panel закрывается после выбора или клика вне panel; локальный `NSPanel.keyDown` обрабатывает стрелки, Enter, Escape и `⌘1–4`, а selection model синхронизирует AppKit-команды со SwiftUI-выделением и автопрокруткой. Mouse monitors не перехватывают клавиатуру и не требуют Input Monitoring для hotkeys.

Связанные файлы: `MacCleaner/Services/ClipboardHistoryService.swift`, `MacCleaner/Views/UtilityToolsView.swift`, `MacCleaner/MacCleanerApp.swift`.

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

## Точечное административное удаление Large Files

Статус: принято

Решение: Large Files сначала перемещает выбранные файлы в Trash обычными правами пользователя. Только для файлов, получивших отказ по доступу, приложение показывает отдельное системное подтверждение администратора и повторяет перемещение точечного списка через macOS authorization prompt. Произвольный shell-ввод, постоянный root helper и хранение пароля не используются.

Обоснование: часть Go/Linux/toolchain-артефактов может быть создана через `sudo` и принадлежать `root`, хотя сама MacCleaner и пользовательские данные приложения от этого не затрагиваются. Автоматически повышать права для всех удалений опасно.

Последствия: пользователь видит, какие именно файлы требуют повышенных прав; отмена запроса оставляет их нетронутыми. Docker, AI-модели и другие `Protected`-категории не получают этот путь автоматически.

## Owner-группы developer и AI данных внутри Junk Files

Статус: принято

Решение: не создавать отдельные вкладки для developer cleanup. `Junk Files` показывает отдельные стабильные owner-строки для Xcode, менеджеров зависимостей, языковых toolchains, IDE, AI-кэшей и проектных артефактов. Каждая строка объясняет, что именно будет удалено и потребуется ли пересборка или повторная загрузка.

Обоснование: пользователю нужно выбрать конкретный источник занятого места, а не принимать непрозрачный общий `User Cache`. При этом отдельные вкладки сделали бы Storage-функцию фрагментированной.

Последствия: selection хранится по owner ID, а не только по широкому типу `JunkType`. Git-проекты с незакоммиченными изменениями требуют подтверждения; открытые браузеры закрываются только после подтверждения обычным terminate-запросом. Модели AI и Docker Desktop data защищены от массовой очистки. Удаление остаётся Trash-only.

Связанные файлы: `MacCleaner/Services/StorageAnalyzerService.swift`, `MacCleaner/Views/ContentView.swift`.

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

Решение: использовать Sparkle 2.9.4, HTTPS appcast, EdDSA подпись и шестичасовой интервал автоматических проверок. Ручная команда вызывает foreground `SPUUpdater.checkForUpdates()`, чтобы стандартный user driver владел загрузкой, установкой и перезапуском. Автоматическое расписание не дублируется вызовами из SwiftUI lifecycle; переключатель напрямую меняет `automaticallyChecksForUpdates` и `automaticallyDownloadsUpdates`, уже сохраняемые самим Sparkle.

Обоснование: приложению нужен проверяемый канал доставки исправлений.

Последствия: обновления могут скачиваться из GitHub, проверяться EdDSA и устанавливаться без Developer ID, если приложение находится в записываемом месте, например `/Applications`, а не запущено с read-only DMG. Текущая GitHub DMG распространяется с ad-hoc подписью и предупреждением неизвестного разработчика при первой установке. Developer ID signing и notarization остаются отдельным улучшением доверия и распространения, но не блокируют сам Sparkle update flow.

Release Notes хранятся в единственном файле `MacCleaner/ReleaseNotes.md`, который использует UI и release workflow.

Связанные файлы: `MacCleaner/Services/UpdateService.swift`, `MacCleaner/Info.plist`, `MacCleaner/ReleaseNotes.md`, `.github/workflows/release.yml`, `MacCleaner.xcodeproj/project.pbxproj`.

## Статический промо-сайт без runtime-зависимостей

Статус: принято

Решение: хранить продуктовый сайт в `website/` как самодостаточные HTML, CSS и vanilla JavaScript; для продуктовых превью использовать полные снимки реального интерфейса приложения, а не приближённую HTML/CSS demo-модель. Окружение macOS и корпус MacBook остаются CSS-слоем, чтобы снимок приложения показывался обычным окном с menu bar, Dock и traffic-light controls.

Обоснование: сайту не нужен backend или сложный UI runtime; статическая реализация быстро загружается, легко публикуется и не добавляет зависимости в Swift-проект.

Последствия: данные сайта не синхронизируются с app target автоматически; при изменении версии, системных требований, продуктовых ограничений или интерфейса текст и снимки необходимо обновлять явно. Hero использует системный захват окна без указателя мыши; все 11 кадров нормализуются до `2600 × 1576` и отображаются в общей геометрии без изменения пропорций. Служебный индикатор Screen Recording маскируется нейтральной областью native window chrome, после чего traffic-light controls восстанавливаются CSS-слоем. Перед публичной публикацией снимки необходимо отдельно проверить на допустимость показанных локальных значений и идентификаторов. Интерактив остаётся на vanilla JavaScript и не выполняет действий внутри приложения.

Связанные файлы: `website/index.html`, `website/styles.css`, `website/script.js`.

## Связанные материалы

- [[Architecture]]
- [[Features]]
- [[Opportunities]]
