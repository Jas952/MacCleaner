# Decisions

## Нативное macOS-приложение

Статус: принято

Решение: SwiftUI является основным UI-слоем; AppKit, CoreGraphics, IOKit, AVFoundation и Vision используются точечно для системных возможностей.

Обоснование: продукт тесно интегрирован с macOS и должен получать локальные системные данные без отдельного backend.

Связанные файлы: `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Views/`, `MacCleaner/Services/`.

## Локальный диагностический журнал

Статус: принято

Решение: события запуска и агрегированные performance samples хранятся локально через `DiagnosticLogStore`. Пользователь управляет retention, очисткой и экспортом JSON/CSV из отдельной вкладки Other в Settings.

Обоснование: журнал нужен для расследования нагрузки без сервера и без постоянного доступа к пользовательским файлам. В записи не попадают секреты, содержимое файлов или сетевой трафик.

Последствия: журнал ограничен сроком хранения и 2000 записями; полная история per-app sessions, baseline и p95 остаётся отдельным этапом развития наблюдаемости.

Связанные файлы: `MacCleaner/Services/DiagnosticLogStore.swift`, `MacCleaner/Settings/SettingsView.swift`, `MacCleaner/Services/SystemMonitor.swift`.

## Устойчивые thermal/load alerts и background pause

Статус: принято

Решение: `ThermalLoadAlertService` требует три последовательных samples CPU или температуры выше порога перед одним системным уведомлением. Внешняя стеклянная nonactivating-панель показывает CPU как процент и источник температуры (`CPU TEMP`/`SoC TEMP`), сама скрывается через 5 секунд и позволяет перейти в Processes. При неактивной scene `SystemMonitor` отключает process/disk/window collectors и работает в редком lightweight режиме; при возврате немедленно выполняется полный refresh.

Пороговые значения и общий переключатель предупреждений вынесены в Settings → Notifications и сохраняются через `UserDefaults`; это позволяет менять чувствительность без изменения кода или перезапуска приложения.

Обоснование: одиночный всплеск не должен создавать шум, а скрытое приложение не должно продолжать дорогой сбор данных. Lightweight режим сохраняет возможность предупредить пользователя о длительном перегреве.

Ограничения: панель не использует активацию приложения при появлении и закрывается только действием пользователя. Кнопка `Open Processes` явно активирует приложение и переводит его в нужную вкладку; журнал продолжает работать локально даже если панель закрыта.

Связанные файлы: `MacCleaner/Services/ThermalLoadAlertService.swift`, `MacCleaner/Services/SystemMonitor.swift`, `MacCleaner/MacCleanerApp.swift`.

## Единый каталог включаемых инструментов

Статус: принято

Решение: доступность Tools, быстрых menu bar actions и menu bar gauges хранится в `SettingsManager`, а метаданные инструментов — в `UtilityToolID`. Tools использует левую selection-driven навигацию; Settings остаётся отдельным системным окном.

Обоснование: большой фиксированный набор горизонтальных переключателей перестал масштабироваться. Единый каталог исключает расхождение между основным окном, Settings и menu bar и позволяет пользователю не загружать интерфейс ненужными функциями.

Последствия: выключенный инструмент исчезает из Tools и быстрого доступа, но его локальные настройки не удаляются. Вводный пункт остаётся всегда. Media Compressor, App Audio Report и Charge Limit помечены `BETA / In development` без переключателя и не попадают в workspace даже при наличии старого persisted ID.

Связанные файлы: `MacCleaner/Models/UtilityTool.swift`, `MacCleaner/Settings/SettingsManager.swift`, `MacCleaner/Views/UtilityToolsView.swift`.

## AppKit status item для модульного menu bar

Статус: принято

Решение: фактический элемент системной строки создаётся через AppKit `NSStatusItem`, а содержимое popover остаётся на SwiftUI. `StatusBarController` размещает passthrough `NSHostingView` внутри `NSStatusBarButton`: gauges без разделителей объединяются по два в вертикальные колонки и сохраняют индивидуальные `Battery / Values` и format-настройки. Если пользователь отключил все gauges, status item использует bundle icon приложения через `NSApplication.applicationIconImage`.

Popover больше не имеет Watch-score и трёхчастного Overview/Details/Tools. System переиспользует реальные `DashboardMetricCard`, `MemoryDashboardCard` и `BatteryDashboardCard`, а отдельный Tools сохраняет быстрые утилиты. Это исключает вторую сокращённую модель карточек и сохраняет одинаковые размеры, данные, графики и accessory battery rings. System/Tools стали icon-only controls возле bundle icon. В Edit drag-handle запускает локальный high-priority direct-drag: исходная точка захвата сохраняется как offset, ScrollView не перехватывает вертикальное перемещение, поднятая карточка следует за указателем без центрирования, а geometry preferences соседних карточек формируют пружинно анимированный временный порядок. После отпускания поднятая копия сначала анимируется к конечной frame, затем одной transaction без анимации заменяется уже находящейся под ней основной карточкой. `SettingsManager` принимает только полный набор модулей без потерь и дубликатов. Один постоянно существующий `TimelineView` использует непрерывную синусоиду только в Edit, поэтому `Done` не меняет identity карточки и гарантированно прекращает колебание. Remove control и dashed restore menu остаются доступны только в Edit.

Обоснование: SwiftUI `MenuBarExtra` обрезал динамическую составную подпись до первого модуля, хотя preview настроек показывал все модули. AppKit-мост сохраняет нативное поведение и даёт предсказуемый контроль реальной ширины status item.

Последствия: контроллер наблюдает общий `SystemMonitor` и `SettingsManager`, поэтому отдельный sampler не создаётся. `MenuBarRefreshDriver` coalesce-ит burst опубликованных monitor-полей, status item обновляется не чаще раза в секунду, а hosting controller не пересоздаётся при каждом клике — это ограничивает SwiftUI layout churn в menu bar. Сам клик по status item показывает transient popover без активации приложения и не поднимает главное окно. Для закрытия по клику в другом приложении используется временный global mouse monitor. Порядок и видимость dashboard-карточек хранятся отдельно от состава status-item gauges; удаление карточки не отключает сборщик и не меняет gauges в menu bar. Визуальная подложка строится на системном `.thinMaterial` и сдержанных semantic tint-слоях, а не на обводках и разделителях, поэтому остаётся адаптивной к фону macOS; короткая alpha-mask ScrollView скрывает оба резких края без отдельного размытого overlay. Header/footer controls имеют стабильную одинаковую hit-area, а рамка и фон возникают только при hover, не меняя layout.

Связанные файлы: `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Settings/SettingsView.swift`.

## Capability-gated системные инструменты

Статус: принято

Решение: Media Compressor, per-app audio и Charge Limit временно не являются доступными Tools. Они остаются в каталоге Settings как beta-задел без переключателя. File Reader — исключение: это рабочий BETA-прототип, поэтому он имеет переключатель и может быть включён для проверки.

Обоснование: восстановление аудиомаршрута и управление зарядом являются hardware/OS-dependent операциями с риском системного побочного эффекта.

Последствия: Screen Text и Awake Profiles удалены из пользовательского каталога; Media Compressor, App Audio Report и Charge Limit видны только как `In development`.

Связанные файлы: `MacCleaner/Views/UtilityToolsView.swift`, `MacCleaner/Services/UtilityToolServices.swift`, `docs/utility-tools-and-menu-bar-analysis.md`.

## Session-only clipboard и глобальные utility hotkeys

Статус: принято

Решение: Clipboard History хранит максимум 12 уникальных элементов только в памяти процесса и наблюдает `NSPasteboard.changeCount`. `⌥C` и `⌥S` регистрируются при запуске процесса через Carbon по физическим key codes; это даёт одинаковое поведение для английской и русской раскладки без глобального перехвата всех нажатий. Clipboard History и Drop Shelf показываются самостоятельными nonactivating `NSPanel`, не активируют главное окно и доступны, пока MacCleaner работает в menu bar или фоне. История использует системный `NSVisualEffectView` (`.popover`, `.behindWindow`) без фиксированной цветовой заливки и видимых action-кнопок. Floating level Drop Shelf меняется узким `NSViewRepresentable`-мостом. Drop Shelf не хранит внешний file URL как рабочий источник: входящий файл копируется в приватный каталог сессии, а каждый drag создаёт новую export-копию и передаёт её через стандартный macOS URL-file provider, чтобы поддержать Finder, Telegram и другие file destinations. Для destination без поддержки drag предусмотрено явное копирование: file URL отправляется как файл, а временные изображения и текст материализуются в системный pasteboard для Cmd+V. Session-копия наружу не публикуется.

Обоснование: SwiftUI scene API не даёт одновременно глобальные layout-independent hotkeys, borderless transient panel с keyboard routing и управляемый `NSWindow.Level`. AppKit используется только на этой границе; данные и выбор остаются SwiftUI/ObservableObject.

Последствия: clipboard не персистится и очищается при завершении MacCleaner. История материализует все доступные representations каждого `NSPasteboardItem`; восстановление и Shelf drag-out сохраняют исходный набор форматов, а не только preview text/image/file URL. Для Drop Shelf исходник пользователя остаётся на месте даже если приложение-получатель перемещает полученный export. History panel закрывается после выбора или клика вне panel; локальный `NSPanel.keyDown` обрабатывает стрелки, Enter, Escape и `⌘1–4`, а selection model синхронизирует AppKit-команды со SwiftUI-выделением и автопрокруткой. Enter после восстановления также отправляет `⌘V` в ранее активное приложение, поэтому отдельная команда вставки не нужна. Mouse monitors не перехватывают клавиатуру и не требуют Input Monitoring для hotkeys.

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

Решение: Large Files сначала перемещает выбранные файлы в Trash обычными правами пользователя. Root-owned файлы исключаются из Select All; при индивидуальном включении checkbox MacCleaner заранее запрашивает системную admin authorization без изменения файла, а реальное перемещение выполняется только после Delete. Произвольный shell-ввод, постоянный root helper и хранение пароля не используются.

Обоснование: часть Go/Linux/toolchain-артефактов может быть создана через `sudo` и принадлежать `root`, хотя сама MacCleaner и пользовательские данные приложения от этого не затрагиваются. Автоматически повышать права для всех удалений опасно.

Последствия: пользователь видит, какие именно файлы требуют повышенных прав; отмена запроса снимает их выделение и оставляет нетронутыми. Docker, AI-модели и другие `Protected`-категории не получают этот путь автоматически.

## Owner-группы developer и AI данных внутри Junk Files

Статус: принято

Решение: не создавать отдельные вкладки для developer cleanup. `Junk Files` показывает отдельные стабильные owner-строки для Xcode, менеджеров зависимостей, языковых toolchains, IDE, AI-кэшей и проектных артефактов. Каждая строка объясняет, что именно будет удалено и потребуется ли пересборка или повторная загрузка.

Обоснование: пользователю нужно выбрать конкретный источник занятого места, а не принимать непрозрачный общий `User Cache`. При этом отдельные вкладки сделали бы Storage-функцию фрагментированной.

Последствия: selection хранится по owner ID, а не только по широкому типу `JunkType`. Git-проекты с незакоммиченными изменениями требуют подтверждения; открытые браузеры закрываются только после подтверждения обычным terminate-запросом. Модели AI и Docker Desktop data защищены от массовой очистки. Удаление остаётся Trash-only.

Связанные файлы: `MacCleaner/Services/StorageAnalyzerService.swift`, `MacCleaner/Views/ContentView.swift`.

## Bounded scanners

Статус: принято

Решение: файловые анализаторы имеют общие entry/time budgets, cancellation и режимы Efficient/Thorough. Единый Opt использует Efficient как базовый проход, позволяет выбрать roots и кэширует уже проверенные roots до завершения сессии, чтобы повторный анализ не обходил те же места без явного сброса.

Обоснование: неограниченный обход home или диска блокирует UI и создаёт неконтролируемый I/O.

Последствия: результат может быть ограниченным; интерфейс и документация не должны называть его полным forensic scan.

Связанные файлы: `MacCleaner/Services/ScanResourceBudget.swift`, `StorageAnalyzerService.swift`, `DuplicateFinderService.swift`, `SimilarPhotoService.swift`, `CloudReclaimService.swift`.

## Единый Opt вместо Pro-очистки

Статус: принято

Решение: отдельный режим Pro для очистки не используется. Opt объединяет быстрый анализ RAM, disk junk, DNS и system refresh, но перед очисткой показывает список найденных элементов по категориям и путям. Startup Optimizer вынесен в самостоятельный раздел Startup. Глубина disk-сканирования управляется выбранными roots и повторно не запускается для уже проверенных roots в рамках текущей сессии.

Обоснование: два режима очистки не давали доказанного дополнительного результата, а пользователю важнее прозрачный список действий и контроль области анализа. Startup имеет другой жизненный цикл и обратимую операцию disable/restore, поэтому не должен запускаться из однокнопочной очистки.

Последствия: Pro-переключатель удалён из sidebar. Для добавления новых областей пользователь включает соответствующие roots и запускает Opt снова; ранее проверенные roots переиспользуются без повторного обхода.

Дополнение по интерфейсу: после анализа Opt раскрывает отдельный полноразмерный review-экран. Категории, пути и чекбоксы занимают всю доступную область, а очистка запускается отдельной кнопкой в нижней панели. Центральный круг скрывается на время review и возвращается после cleanup вместе со сводным результатом.

Порядок интерфейса: области сканирования распределены по двум фиксированным колонкам, а найденные файлы внутри категории упорядочиваются по размеру и затем по пути. Так повторный анализ не меняет визуальный порядок строк из-за порядка обхода файловой системы.

Для ready-состояния scope скрыт по умолчанию и раскрывается центральной стрелкой, чтобы основной экран не превращался в длинную форму настроек. Storage Junk использует тот же review-язык: сводные метрики сверху, категории с раскрываемыми путями и явные `Cancel`/`Done`/`Clean` действия внизу.

Тот же footer-паттерн применяется к Optimize Cleanup Report: выход из review не должен выглядеть как единственная destructive-кнопка, поэтому Cancel и Done видимы постоянно, а Clean доступна только при непустом выборе.

Визуальная иерархия Optimize Report синхронизирована с Junk Report: серый используется для общей информации и нейтральных поверхностей, а цвет оставлен только для семантических акцентов. Scope раскрывается компактно и без перемещения большого блока, чтобы не пересекаться с кругом действия.

Startup добавлен в Optimize как ненавязчивый переходный ряд, а не как четвёртая большая карточка. Так пользователь видит связанную функцию рядом с tune-up, но операции LaunchAgents остаются отдельными и не смешиваются с автоматической очисткой.

Startup намеренно убран из левого списка: Optimize становится точкой входа для связанных maintenance-функций, а отдельный экран сохраняет собственное пространство и lifecycle.

Связанные файлы: `MacCleaner/Views/CleanerView.swift`, `MacCleaner/Views/ContentView.swift`, `MacCleaner/Services/CleanerService.swift`, `MacCleaner/Services/StartupOptimizerService.swift`.

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

## Apple Silicon fan control requires a privileged helper

Статус: в работе

Решение: мониторинг вентиляторов на Apple Silicon должен читать реальные SMC-ключи `FNum`/`FpNm` и `F%dAc`, не создавать модельные placeholder-записи. Запись ручного режима не выполняется из SwiftUI-процесса: для M-чипов нужен постоянный подписанный privileged helper с XPC/SMJobBless, который пробует `F%dMd` и `F%dmd`, а на поколениях с `Ftst` поддерживает диагностическую последовательность и восстановление Auto после сна/завершения.

Обоснование: текущий Intel-путь `FS! `/`F%dTg` не управляет Apple Silicon и создавал ложные RPM. Ограничение записи связано с root/firmware thermal policy, а не с платной подпиской само по себе; Developer ID нужен для установки и подписания privileged helper через SMJobBless и для нормального распространения.

Последствия: до добавления helper приложение показывает только фактически доступную телеметрию и не обещает ручное управление. Реализация control path должна быть отдельным target/helper с безопасным IPC, arbitration нескольких клиентов и обязательным возвратом в системный режим.

Связанные файлы: `MacCleaner/Services/SMCService.swift`, `docs/knowledge/Opportunities.md`.

Дополнение: helper теперь является отдельным Xcode target `MacCleanerFanHelper`, встраивается в `Contents/Library/LaunchServices`, а установка вызывается через `SMJobBless` с `SMPrivilegedExecutables`/`SMAuthorizedClients` и встроенным launchd plist для Mach service. Helper отклоняет XPC-клиентов, не соответствующих code-signing requirement MacCleaner, проверяет FPE2 bounds до преобразования и при неудачной записи RPM возвращает fan mode и `Ftst` в Auto. Сборка без подписи намеренно проверяет только структуру и компиляцию; end-to-end bless требует Developer ID-сертификат и реальный Apple Silicon Mac.

## Retire legacy root helper

Статус: принято

Решение: неиспользуемый daemon source удалён из `SystemMonitor.swift`; новый `HelperManager` умеет только обнаружить и удалить прежнюю установку.

Обоснование: legacy daemon принимал unauthenticated HTTP-команды на localhost с root-правами.

Последствия: функции используют user-scoped APIs; старый helper можно удалить с подтверждением администратора.

Связанный файл: `MacCleaner/Services/SystemMonitor.swift`.

## Usage Codex через локальный app-server

Статус: принято

Решение: не вычислять лимиты по размеру `~/.codex` или локальным transcript-файлам. Agents вызывает официальный read-only метод Codex app-server `account/rateLimits/read`, отображает `usedPercent` как остаток окна и дату `resetsAt`, а ответ кэшируется на 60 секунд.

Обоснование: usage является account-level backend-состоянием; локальные сессии содержат историю и token counters, но не являются надёжным источником текущей квоты. При недоступной авторизации или backend UI показывает `Unavailable`.

Последствия: MacCleaner не получает и не сохраняет токены, не выполняет login/logout и не изменяет Codex config. Вызов выполняется только при открытом Agents и наличии Codex.

Связанные файлы: `MacCleaner/Services/AIWorkloadService.swift`, `MacCleaner/Views/AIWorkloadViews.swift`.

## Consumer-aware мониторинг

Статус: принято

Решение: cadence `SystemMonitor` зависит от активных экранов.

Обоснование: process snapshots, sensors и `system_profiler` не должны работать с одинаковой частотой, когда их никто не отображает.

Связанный файл: `MacCleaner/Services/SystemMonitor.swift`.

## Графики menu bar используют общую thermal-телеметрию

Статус: принято

Решение: раздел `Graphs` использует общий `SystemMonitor`, а `ProcessHistoryStore` материализует process snapshots в локальный четырёхчасовой архив. Открытый popover регистрирует consumer `graphs`, немедленно запрашивает processes и sensors и затем использует общий 15-секундный tick. Forced refresh flags объединяются, если монитор занят, и выполняются следующим проходом вместо потери запроса. При background-suspended UI отдельный облегчённый путь раз в пять минут выполняет только bounded process snapshot без window collector. Архив ограничен 1 000 samples, очищается по timestamp, не сохраняет аргументы командной строки и пишет полный JSON не чаще раза в минуту. CPU/Memory/Energy визуализируются независимыми линиями с иконками 30 минут/4 часа внутри графика, максимум 180 render-точками и честными разрывами при пропуске cadence. Первый и второй samples разрешены как стартовая точка/линия до включения обычного transient-фильтра. Для каждого выбора метрики и интервала `MenuBarProcessHistoryView` создаёт один индексированный render snapshot вместо повторной фильтрации четырёхчасового архива внутри вычисления каждой точки. История процессов не подписана на весь `SystemMonitor`. Graph modes сохраняют стабильные view roots после первой загрузки; скрытая Thermal surface приостанавливает TimelineView и игнорирует промежуточные sensor animation updates, чтобы быстрый возврат не создавал фоновую нагрузку. Изометрическая поверхность интерполирует только доступные readings по зонам компонентов; геометрия базы выбирается по семейству MacBook Air/Pro и сверяется с официальной component layout Apple. Точные координаты датчиков и фактический MagSafe/USB-C active port не выдумываются, потому что публичная macOS API не предоставляет их стабильно для каждого model identifier. Вращение, zoom, component hover, скрытие heat layer, разнесение двух слоёв и плавная интерполяция между samples являются только view-state и не изменяют исходную телеметрию. Reset возвращает ракурс и масштаб; split/join выполняются явной покадровой последовательностью после camera reset. AppleSMC ABI фиксируется тестом на 80 bytes, а fan RPM декодируется по declared `flt `/`fpe2` type. Пространственный воздушный поток и L/R RPM status привязаны к `FanInfo.actualRPM`, а charging pulse — к `BatteryInfo.isCharging`.

Дополнение по устойчивости process-линий: единичный peak не является основанием для включения серии. Roster использует накопленный вклад и минимальное присутствие; небольшие sampling gaps интерполируются, вход/выход соединяется с нулём, а короткие runs скрываются. Это сохраняет читаемость при старте, завершении и перезапуске процессов без дополнительного sampler или таймера.

Исключение быстрого старта: значимые identities из последнего sample добавляются перед stability-ranked roster с устранением дубликатов. Это предотвращает состояние, когда summary уже показывает текущий процесс, а Canvas остаётся пустым из-за недостаточного sample count; фильтрация устойчивости применяется к остальной истории.

Дополнение по целостности архива: stable identity не считается гарантированно уникальным входом. Если один collector sample содержит несколько записей с одинаковым identity, `ProcessHistoryStore` суммирует CPU, память и instance count, сохраняя метаданные первого представителя. Нормализация выполняется на входе и после декодирования прежнего JSON; render-path использует тот же безопасный индекс и не создаёт `Dictionary(uniqueKeysWithValues:)` из недоверенного архива.

Дополнение по шкалам: верхняя граница Y не подстраивается под случайный самый большой процесс. Для CPU и activity `ps %CPU` делится на число логических процессоров, где полная загрузка Mac равна 100%; для Memory пределом служит физическая RAM из `ProcessInfo`. Линейная шкала является исходной, логарифмический режим — обратимой экранной трансформацией `log1p`; оба не изменяют архив. Четырёхчасовое представление использует 72 равномерных bucket с медианой и трёхточечным сглаживанием вместо соединения сырых 15-секундных samples. Пропуск завершает сегмент без точки 0; общие collector gaps до 15/30 минут соединяет самостоятельный dashed bridge, который не участвует в hover как измерение. Промежуточные системные samples без выбранного identity доказывают завершение процесса и запрещают bridge. Area fill отключён, активный minor-filter оставляет четыре главные серии, а порог пика 1% влияет только на roster.

Публичный `CMMotionManager` помечен Apple как unavailable в macOS, поэтому текущая версия не имитирует физическую ориентацию MacBook по движению курсора. Автоматическая ориентация допустима только при появлении публичного chassis-motion API или после отдельно согласованного внешнего motion-source.

Дополнение: RAM utilization не является thermal reading и не влияет на высоту поверхности. Battery показывается как единый pack без неподтверждённого cell count. Конкретный power connector разрешается только через model-specific IORegistry mapping: для проверенного Mac15,6 порядок контроллеров — USB-C 1, USB-C 2, MagSafe 3, USB-C 3; неизвестные модели получают generic-подпись. Одновременно рисуется только активный кабель. Component inspection выполняет top-down camera transition до скрытия mesh, а zoom slider раскрывается из отдельной icon-only кнопки.

Обоснование: единый collector сохраняет consumer-aware cadence и не удваивает обращения к AppleSMC/IOHID. Отделение физической схемы от температурных данных позволяет честно пропускать недоступные sensors и расширять model-specific layouts без изменения `SystemMonitor`.

Проверка перед `v1.0.8` на MacBook Pro 14″ M3 Pro: 15-секундный idle snapshot Release-сборки показал 1,24% CPU и 133,3 MB RSS против 1,93% CPU и 123,8 MB RSS у установленной `v1.0.7`. Абсолютный прирост памяти около 9,5 MB принят как стоимость bounded четырёхчасового архива и двух новых графических экранов; idle CPU не вырос. В Debug-проверке открытый Process History занимал 1,79% одного ядра, Thermal Surface — 5,40% одного ядра при активном экране, то есть около 0,5% общей мощности 11 логических ядер.

Связанные файлы: `MacCleaner/MenuBar/MenuBarGraphsView.swift`, `MacCleaner/MenuBar/MenuBarProcessHistoryView.swift`, `MacCleaner/MenuBar/ProcessHistoryStore.swift`, `MacCleaner/MacCleanerApp.swift`, `MacCleaner/Services/SystemMonitor.swift`.

## Нативные tooltip и компактные Tools

Статус: принято

Решение: пояснения Device Health показываются системным hover tooltip через `.help`, а не отдельным модальным окном. File Reader и остальные незавершённые beta-инструменты остаются видимыми в Settings, но исключаются из активного Tools sidebar. Для Homebrew и Color Picker используются общие contrast-safe action controls; Physical Maintenance и Speaker Test получают компактный ToolPage без лишнего вертикального скролла. Drop Shelf в рабочем Tools-разделе оставляет только настройки, тогда как реальная drop-зона принадлежит floating panel.

Обоснование: короткие пояснения и действия должны оставаться рядом с контекстом и не прерывать диагностику модальным overlay; beta-функция не должна выглядеть доступной, если пользователь не может надёжно завершить сценарий.

## Sparkle для обновлений

Статус: принято

Решение: использовать Sparkle 2.9.4, HTTPS appcast, EdDSA подпись и шестичасовой интервал автоматических проверок. Ручная команда вызывает foreground `SPUUpdater.checkForUpdates()`, чтобы стандартный user driver владел загрузкой, установкой и перезапуском. Автоматическое расписание не дублируется вызовами из SwiftUI lifecycle; переключатель разрешает только `automaticallyChecksForUpdates`, а `automaticallyDownloadsUpdates` принудительно выключен — найденное обновление не меняет приложение без явного сценария пользователя.

Обоснование: приложению нужен проверяемый канал доставки исправлений.

Последствия: обновления могут скачиваться из GitHub, проверяться EdDSA и устанавливаться без Developer ID, если приложение находится в записываемом месте, например `/Applications`, а не запущено с read-only DMG. Текущая GitHub DMG распространяется с ad-hoc подписью и предупреждением неизвестного разработчика при первой установке. Developer ID signing и notarization остаются отдельным улучшением доверия и распространения, но не блокируют сам Sparkle update flow.

Release Notes хранятся в единственном публикуемом файле `MacCleaner/ReleaseNotes.md`, который использует release workflow. Updates UI показывает состояние Sparkle без второй копии changelog. Формат и процедура публикации закреплены в `docs/knowledge/github/GitHubAndReleases.md`.

Связанные файлы: `MacCleaner/Services/UpdateService.swift`, `MacCleaner/Info.plist`, `MacCleaner/ReleaseNotes.md`, `.github/workflows/release.yml`, `MacCleaner.xcodeproj/project.pbxproj`.

## Статический промо-сайт без runtime-зависимостей

Статус: принято

Решение: хранить продуктовый сайт в `website/` как самодостаточные HTML, CSS и vanilla JavaScript; для продуктовых превью использовать полные снимки реального интерфейса приложения, а не приближённую HTML/CSS demo-модель. Окружение macOS и корпус MacBook остаются CSS-слоем, чтобы снимок приложения показывался обычным окном с menu bar, Dock и traffic-light controls.

Обоснование: сайту не нужен backend или сложный UI runtime; статическая реализация быстро загружается, легко публикуется и не добавляет зависимости в Swift-проект.

Последствия: данные сайта не синхронизируются с app target автоматически; при изменении версии, системных требований, продуктовых ограничений или интерфейса текст и снимки необходимо обновлять явно. Hero использует системный захват окна без указателя мыши; все 11 кадров нормализуются до `2600 × 1576` и отображаются в общей геометрии без изменения пропорций. Служебный индикатор Screen Recording маскируется нейтральной областью native window chrome, после чего traffic-light controls восстанавливаются CSS-слоем. Перед публичной публикацией снимки необходимо отдельно проверить на допустимость показанных локальных значений и идентификаторов. Интерактив остаётся на vanilla JavaScript и не выполняет действий внутри приложения.

Связанные файлы: `website/index.html`, `website/styles.css`, `website/script.js`.

## Быстрый старт Process History не блокируется общей телеметрией

Статус: принято

Решение: Graphs сначала записывает уже доступные `processNodes`; consumer `graphs` не включает window collector и не вызывает disk refresh на каждом process tick. Sensor/battery refresh не блокирует первый process sample.

## Связанные материалы

- [[Architecture]]
- [[Features]]
- [[Opportunities]]
