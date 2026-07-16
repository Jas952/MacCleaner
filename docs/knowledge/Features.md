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
- Настраиваемый Tools workspace: вертикальная sidebar/detail-композиция, обязательный вводный экран и ручное включение каждого инструмента в отдельном окне Settings.
- Network Test использует компактную последовательность speed, latency и connection-profile секций без принудительной минимальной высоты и распределяющих пустое место spacer-блоков.
- Input Test размещает шестирядную keyboard matrix в контейнере фактической высоты и прижимает её к верхнему краю, поэтому между статистикой, клавиатурой и журналом событий нет искусственных вертикальных пустот.
- Полноразмерные Tools detail-экраны с единым header, согласованными высотами парных panels/metric cards и дополнительным полезным контентом в коротких diagnostics.
- Floating Drop Shelf: самостоятельная nonactivating utility-панель для file references, изображений и временного текста с drag-in/drag-out, локальной настройкой pin/unpin и глобальной командой `⌥S`; вызов не открывает главное окно, пока MacCleaner работает в фоне. Действия Open Shelf и Show History стоят сразу после заголовков карточек в компактном размере, Add Clipboard и Clear также оформлены нейтральными icon-only controls с tooltip/accessibility labels; верхние Floating Shelf и Clipboard History автоматически получают одинаковую высоту по более высокой карточке, а pin switch использует компактный нейтральный `MutedSwitchStyle` без яркого accent tint.
- Clipboard History: компактная session-only история до 12 текстов, изображений и наборов файлов; глобальная команда `⌥C` работает по физической клавише в английской и русской раскладках и показывает только адаптивную системную vibrancy-панель без открытия главного окна. Видимых action-кнопок нет: двойной клик восстанавливает запись, очистка доступна из контекстного меню, `⌘1–4` восстанавливает первые четыре элемента.
- Clipboard/Shelf round-trip сохраняет все доступные pasteboard representations исходной записи, включая plain text, RTF/HTML, изображения и file URLs; preview остаётся упрощённым, но повторное использование и drag-out не сводят данные к preview-формату.
- Clipboard History при открытии выделяет самый свежий элемент; стрелки вверх/вниз перемещают выделение с автопрокруткой, Enter восстанавливает выбранную запись и закрывает панель, а `⌘1–4` остаются быстрыми командами первых четырёх элементов.
- Color Picker через `NSColorSampler` с HEX/RGB/HSB, sRGB-предупреждением и временной историей восьми последних цветов.
- Media Compressor сохранён как beta-задел, но временно не доступен в Tools.
- Homebrew Maintenance: обнаружение пользовательского brew, audit outdated, выбор пакетов, подтверждаемое upgrade и cleanup dry-run перед подтверждаемой очисткой.
- App Audio Report и Charge Limit сохранены как beta-задел, но временно не доступны в Tools.
- Модульный menu bar: выбираемые CPU/RAM/GPU/temperature/battery gauges представлены draggable tiles с ведущей handle вместо стрелок; системный preview переносит всю плитку без смещения, а список анимированно раздвигается при hover. Общий режим `Battery / Values`, текущие значения, сохраняемый left-to-right order и индивидуальные однобуквенные форматы остаются независимыми настройками; quick tools занимают полную ширину секции и включаются нативными checkbox слева от названия.
- В status item режим `Battery` показывает выровненные вертикальные indicators с load/heat fill, semantic green/orange/red, temperature thermometer и окрашенный тем же semantic color compact format marker (`%/C`, `%/G`, `%/°`, `C/F`, `%/clock`). Режим `Values` заменяет battery на непосредственные проценты или числа с единицей измерения. Оба режима используют одинаковые `CPU`, `RAM`, `GPU`, `TEMP`, `BAT` labels, dividers, accessibility values и live preview в Settings. При отключении всех gauges остаётся настоящий значок приложения MacCleaner.
- Menu bar modules визуально разделены тонкими dividers; short labels увеличены до сопоставимого с battery кегля, а термометр стоит после temperature battery.
- Updates: Sparkle, подписанный EdDSA appcast, шестичасовые автоматические проверки и общий About & Updates overlay. Ручная команда открывает штатный сценарий Download → Install → Relaunch; автоматический режим управляет одновременно проверкой и фоновой загрузкой без отдельного дублирующего `UserDefaults`.

### UI и качество

- Общий design system, modal overlay, segmented control и контрастные button styles.
- Launch intro и фиксированное desktop window layout.
- Адаптивный англоязычный промо-сайт в `website/` с физически разделённой анимацией закрытого и открытого MacBook: оба состояния используют один масштаб и шарнир, а строгая передача между ними исключает одновременное появление двух корпусов. На внешней крышке расположен защитный знак; открытое состояние включает ограниченную по перспективе клавиатурную деку, полноценный macOS desktop внутри экрана и последовательное переключение всех 11 основных sidebar-разделов по чистым системным кадрам. Carousel поддерживает стрелки, горизонтальные вкладки, клавиатуру и клики по реальной боковой панели. Нижние product stories отдельно рассказывают о system overview, AI Agents и maintenance/diagnostics; остальные возможности собраны без повторения carousel. Фон первого экрана использует анимированные mesh-gradient, glass-orbit и light-plane слои и реагирует на движение указателя; предусмотрен `prefers-reduced-motion`.
- 46 safety/policy XCTest-тестов; текущий test run проходит.

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
- Screen Text и Awake Profiles не входят в runtime-каталог Tools до отдельной готовой реализации и продуктовой проверки.
- Media Compressor, App Audio Report и Charge Limit показываются только как beta в Settings и не входят в runtime-sidebar.

## Связанные материалы

- [[Product]]
- [[Architecture]]
- [[Decisions]]
- [[Opportunities]]
