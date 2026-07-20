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
- Единый Opt-сценарий: сначала показывается подробный список найденных disk-junk элементов с путями, категориями и чекбоксами, затем очищаются только выбранные элементы через Trash. Пользователь выбирает roots сканирования; уже проверенные roots повторно не обходятся в текущей сессии, а новые roots можно добавить позже.
- После сканирования Opt переключается в полноразмерный экран отчёта: круг запуска скрывается, список категорий и путей занимает рабочую область, а отдельная нижняя кнопка запускает очистку выбранных элементов. После завершения очистки экран возвращается к компактному кругу и сводному отчёту.
- Перед сканированием области выбираются в двух ровных колонках со стабильным порядком; после сканирования элементы внутри категорий сортируются по размеру и показываются в одинаковых строках с фиксированной зоной выбора.
- Scan scope в Opt по умолчанию свёрнут и раскрывается тонкой центральной кнопкой-стрелкой; Cleanup Report использует карточку сводных метрик и единый список категорий/путей.
- Ready-состояние Optimize содержит компактную строку Startup с нейтральной иконкой и переходом в отдельный Startup Optimizer; она не запускает анализ автоматически и не дублирует список LaunchAgents.
- Startup скрыт из основного левого списка, но остаётся доступен через строку Startup внутри Optimize.
- Общая информация Cleanup Report Opt использует нейтральную серую иерархию Junk Report; цвет сохраняется только у чекбоксов, иконок категорий и основной кнопки действия. Раскрытый Scan scope уменьшен по высоте и анимируется коротким opacity-переходом.
- Внизу Cleanup Report Opt постоянно доступны `Cancel`, `Done` и `Clean`: первые две кнопки закрывают review без запуска удаления, а `Clean` становится активной только при выбранных элементах.
- Startup Optimizer вынесен в отдельный раздел Startup и не смешивается с однокнопочной очисткой Opt.

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
- Junk Files owner-группы: Xcode DerivedData/Archives/Device Support/Simulator data и runtimes, SwiftPM, CocoaPods, Carthage, Homebrew, npm/Yarn/pnpm, Python pip/uv, Gradle/Maven/Android Studio, Cargo, Go, JetBrains, Blender, VS Code/Cursor/Claude caches и артефакты Unity/Unreal/Godot/web/Swift/Rust/Python-проектов. Каждая категория раскрывается в список путей с размерами; большое количество мелких файлов сворачивается в агрегированную строку папки. Безопасные и пересоздаваемые данные (`safe`, `rebuild`, `redownload`) автоматически отмечены чекбоксами, требующие проверки (`review`, `protected`) — нет.
- Storage → Junk Files после анализа показывает такой же подробный review-экран: карточку метрик, категории с раскрытием путей и нижнюю панель с отдельными `Cancel`, `Done` и `Clean` действиями.
- Артефакты web/Swift/Rust/Python/Unity/Unreal-проектов находятся только в известных папках проектов с bounded scan; исходный код не сканируется как кандидат на удаление. Для Git-проекта с незакоммиченными изменениями требуется явное подтверждение.
- Открытые Chrome/Safari/Firefox/Edge/Brave перед очисткой кэша требуют подтверждения и закрываются обычным запросом завершения; принудительный kill отсутствует.
- Если временный cache-файл исчез между сканированием и перемещением в Trash, очистка считает его уже разрешённым элементом, убирает устаревшую категорию из результата и не показывает ложную ошибку `The file doesn’t exist`.
- Hugging Face/папки локальных Ollama-моделей и Docker Desktop data отображаются как защищённые данные: они не входят в массовое удаление, потому что могут содержать модели, базы и рабочее состояние.
- Защищённые категории скрыты в результатах Junk Files по умолчанию; кнопка «Показать защищённые» раскрывает их только для обзора и не добавляет в очистку.
- Large Files при отказе macOS в доступе предлагает отдельное подтверждение административного удаления только для неудачных выбранных файлов; без подтверждения файлы остаются на месте.

### Дополнительные инструменты

- Desktop Manager: grid/list/columns/canvas, preview, metadata, rename, move, organization и Trash.
- Pake Apps: создание standalone web apps через внешний `pake` CLI и управление установленными результатами.
- AI Agents: локальные agent processes, Codex/Claude/Gemini profiles, MCP, skills и components. Для Codex реальные 5-hour/weekly rate limits и время сброса через локальный app-server показываются компактно в правом блоке карточки; при недоступной авторизации показывается `Unavailable`.
- AI Indexes: обнаружение локальных index stores.
- LLM Library: модели, фильтры и fit-оценка через `llmfit`.
- Fans: SMC/thermal readings и fan UI при поддержке оборудования.
- Physical Maintenance: screen dim, keyboard lock и combined mode.
- Diagnostics: keyboard, pointer, speakers, storage health, APFS integrity, SSD SMART, thermal power и network.
- Настраиваемый Tools workspace: вертикальная sidebar/detail-композиция, обязательный вводный экран и ручное включение каждого инструмента в отдельном окне Settings.
- Network Test использует компактную последовательность speed, latency и connection-profile секций без принудительной минимальной высоты и распределяющих пустое место spacer-блоков.
- Input Test размещает шестирядную keyboard matrix в контейнере фактической высоты и прижимает её к верхнему краю, поэтому между статистикой, клавиатурой и журналом событий нет искусственных вертикальных пустот.
- Полноразмерные Tools detail-экраны с единым header, согласованными высотами парных panels/metric cards и дополнительным полезным контентом в коротких diagnostics.
- Floating Drop Shelf: самостоятельная nonactivating utility-панель для session-owned копий файлов, изображений и временного текста с drag-in/drag-out, локальной настройкой pin/unpin и глобальной командой `⌥S`; исходный файл не перемещается и не изменяется, а каждый drag-out создаёт новую export-копию. Провайдер использует стандартный macOS URL-file provider для этой export-копии, поэтому файл можно отправить в Finder, Telegram, редактор или другое приложение, которое принимает файлы. Для приложений, которые не принимают drag, у записи есть отдельная кнопка Copy for paste: file URL копируется как файл, а временные изображения и текст материализуются в системный pasteboard для Cmd+V. Вызов не открывает главное окно, пока MacCleaner работает в фоне. Окно использует простой empty state с тремя ярлыками `Drop in`, `Drag out`, `Safe copy`, а у каждой записи явно показаны действия Drag out и Copy for paste. Действия Open Shelf и Show History стоят сразу после заголовков карточек в компактном размере, Add Clipboard и Clear также оформлены нейтральными icon-only controls с tooltip/accessibility labels; верхние Floating Shelf и Clipboard History автоматически получают одинаковую высоту по более высокой карточке, а pin switch использует компактный нейтральный `MutedSwitchStyle` без яркого accent tint.
- Clipboard History: компактная session-only история до 12 текстов, изображений и наборов файлов; глобальная команда `⌥C` работает по физической клавише в английской и русской раскладках и показывает только адаптивную системную vibrancy-панель без открытия главного окна. Видимых action-кнопок нет: двойной клик восстанавливает запись, очистка доступна из контекстного меню, `⌘1–4` восстанавливает первые четыре элемента.
- Clipboard/Shelf round-trip сохраняет все доступные pasteboard representations исходной записи, включая plain text, RTF/HTML, изображения и file URLs; preview остаётся упрощённым, но повторное использование и drag-out не сводят данные к preview-формату.
- Clipboard History при открытии выделяет самый свежий элемент; стрелки вверх/вниз перемещают выделение с автопрокруткой, Enter восстанавливает выбранную запись, автоматически отправляет `⌘V` в предыдущее активное приложение и закрывает панель, а `⌘1–4` остаются быстрыми командами первых четырёх элементов.
- Color Picker через `NSColorSampler` с HEX/RGB/HSB, sRGB-предупреждением и временной историей восьми последних цветов.
- File Reader (BETA) открывает любой локальный файл: показывает нативный preview для изображений и PDF, UTF-8 для текста и hex fallback для бинарных форматов; файл не загружается и не изменяется.
- Media Compressor сохранён как beta-задел, но временно не доступен в Tools.
- Homebrew Maintenance: обнаружение пользовательского brew, audit outdated, выбор пакетов, подтверждаемое upgrade и cleanup dry-run перед подтверждаемой очисткой.
- App Audio Report и Charge Limit сохранены как beta-задел, но временно не доступны в Tools.
- Модульный menu bar: выбираемые CPU/RAM/GPU/temperature/battery gauges представлены draggable tiles с ведущей handle вместо стрелок; системный preview переносит всю плитку без смещения, а список анимированно раздвигается при hover. Каждый gauge независимо выбирает `Battery / Values` и формат через две компактные icon-only segmented пары в своей строке; left-to-right order сохраняется отдельно. Прежний общий стиль мигрирует без сброса настроек. Quick tools занимают полную ширину секции и включаются нативными checkbox слева от названия.
- В status item режим `Battery` показывает выровненные вертикальные indicators с load/heat fill, semantic green/orange/red, temperature thermometer и окрашенный тем же semantic color compact format marker (`%/C`, `%/G`, `%/°`, `C/F`, `%/clock`). Режим `Values` заменяет battery на непосредственные проценты или числа с единицей измерения. Оба режима используют одинаковые `CPU`, `RAM`, `GPU`, `TEMP`, `BAT` labels, dividers, accessibility values и live preview в Settings. При отключении всех gauges остаётся настоящий значок приложения MacCleaner.
- Menu bar modules визуально разделены тонкими dividers; short labels увеличены до сопоставимого с battery кегля, а термометр стоит после temperature battery.
- Updates: Sparkle, подписанный EdDSA appcast, шестичасовые автоматические проверки и общий About & Updates overlay. Автоматический режим только проверяет наличие обновления; Download → Install → Relaunch запускается явно после найденного обновления.
- General Settings содержит компактную companion-карточку Browser Monitor от того же разработчика: startup-emblem со shield-контуром, краткое описание, основную загрузку ZIP версии 1.0.0, следующую за ней GitHub-ссылку с фирменным знаком и простой локальный popover без декоративных шаговых badges для установки unpacked extension в Chrome.

### UI и качество

- Общий design system, modal overlay, segmented control и контрастные button styles.
- Launch intro и фиксированное desktop window layout.
- Адаптивный англоязычный промо-сайт в `website/` с физически разделённой анимацией закрытого и открытого MacBook: оба состояния используют один масштаб и шарнир, а строгая передача между ними исключает одновременное появление двух корпусов. На внешней крышке расположен защитный знак; открытое состояние включает ограниченную по перспективе клавиатурную деку, полноценный macOS desktop внутри экрана и последовательное переключение всех 11 основных sidebar-разделов по чистым системным кадрам. Carousel поддерживает стрелки, горизонтальные вкладки, клавиатуру и клики по реальной боковой панели. Нижние product stories отдельно рассказывают о system overview, AI Agents и maintenance/diagnostics; остальные возможности собраны без повторения carousel. Фон первого экрана использует анимированные mesh-gradient, glass-orbit и light-plane слои и реагирует на движение указателя; предусмотрен `prefers-reduced-motion`.
- 53 safety/policy XCTest-теста; текущий test run проходит.

## Реализовано с ограничениями

- Settings → Other содержит локальный диагностический журнал: события запуска, периодические агрегированные samples SystemMonitor, retention 7/30/90 дней, ручная очистка и экспорт JSON/CSV.
- При устойчивой высокой CPU-нагрузке или температуре MacCleaner показывает отдельную стеклянную floating warning panel в правом верхнем углу экрана, поверх других окон. Панель содержит CPU в процентах, явно подписанную температуру `CPU TEMP` или `SoC TEMP`, top-3 processes и кнопку `Open Processes`; она не является частью главного окна MacCleaner и автоматически скрывается через 5 секунд. При уходе scene в фон тяжёлый мониторинг и collectors останавливаются; остаётся редкий lightweight режим для предупреждений.
- В Settings → Notifications можно включить/выключить эти предупреждения и отдельно задать порог CPU (50–100%) и температуры (50–110°C). Значения сохраняются локально и применяются без перезапуска приложения.
- Карточка Codex в разделе Agents имеет компактный inline-статус лимитов в правом блоке: подключённый Codex app-server показывает доступное weekly-окно и план; при отсутствии проверенного API/CLI/local source отображается `Unavailable`, без чтения секретов.

- Disk Map ограничен глубиной и budget и не является полным `du` всего диска.
- Large Files, Junk, Duplicates, Similar Photos и Cloud Reclaim ограничены deadlines/entry limits; Thorough расширяет, но не отменяет пределы.
- Similar Photos использует эвристику Vision; финальный выбор остаётся за пользователем.
- Fan control и sensor coverage различаются между Intel и Apple Silicon.
- Advanced SSD требует `smartctl`; thermal power может требовать admin-доступ.
- Pake Apps и LLM Library не работают без внешних CLI.
- Uninstaller не реализует привилегированное удаление root-owned приложений. В Large Files root-owned файлы не попадают в Select All; их индивидуальный checkbox сначала запрашивает admin authorization, а удаление выполняется отдельной кнопкой Delete.
- Обновления готовы на уровне Sparkle/appcast и GitHub Actions; текущая публичная DMG имеет ad-hoc подпись и показывает предупреждение неизвестного разработчика до внедрения Developer ID/notarization.

## Не является текущей функцией

- Установка нового privileged root helper отключена.
- Автоматическое завершение приложений ради очистки RAM отсутствует.
- Необратимый fallback после ошибки Trash отсутствует в мигрированных пользовательских сценариях.
- Полный forensic scan без ограничений не заявлен.
- Screen Text и Awake Profiles не входят в runtime-каталог Tools до отдельной готовой реализации и продуктовой проверки.
- Media Compressor, App Audio Report и Charge Limit показываются только как beta в Settings и не входят в runtime-sidebar.

## Связанные материалы

- [[Product]]
- [[Architecture]]
- [[Decisions]]
- [[Opportunities]]
