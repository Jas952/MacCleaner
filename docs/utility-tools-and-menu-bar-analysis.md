# Расширение Utilities и menu bar

## Цель

Собрать в MacCleaner набор небольших нативных инструментов, которые постоянно нужны в работе с Mac, но не превращать приложение в неконтролируемый набор фоновых процессов. Каждый инструмент должен запускаться по явному действию, использовать локальную обработку и честно показывать ограничения macOS.

## Фактическая основа

- `MenuBarLabel` уже показывает CPU и RAM, использует severity colors и accessibility summary.
- `SystemMonitor` уже получает CPU, RAM, GPU, температуру и батарею, поэтому новый menu bar layout не требует отдельного параллельного sampler.
- `MaintenanceService` уже содержит физические maintenance-сценарии, но постоянного power assertion для предотвращения сна сейчас нет.
- В проекте нет готового per-application audio mixer, screen OCR, color sampler, Homebrew manager или media compressor.

## Внешний референс: Vorssaint Utils

Для `IMP-046`–`IMP-054` использовать [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) как практический ориентир по поведению и lifecycle macOS-утилит. Репозиторий уже объединяет Shelf, per-app volume/output routing, media tools, Homebrew manager, color picker, offline screen OCR, Keep Awake и настраиваемые menu bar readouts.

Что изучать в первую очередь:

- [README](https://github.com/vorssaint/vorssaint-utils/blob/main/README.md) — пользовательские сценарии, feature grouping и graceful degradation;
- [Contributing](https://github.com/vorssaint/vorssaint-utils/blob/main/CONTRIBUTING.md) — границу `UI observes services`, структуру App/Core/Services/UI и self-test подход;
- [Permissions](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PERMISSIONS.md) — optional permissions, объяснение причины доступа и поведение функции при отказе;
- [Privacy](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PRIVACY.md) — local-first обработку, ограниченный список сетевых действий и очистку временных screen-capture данных;
- [License](https://github.com/vorssaint/vorssaint-utils/blob/main/LICENSE) и [Trademarks](https://github.com/vorssaint/vorssaint-utils/blob/main/TRADEMARKS.md) — границы допустимого переиспользования.

Репозиторий является референсом, а не готовой зависимостью MacCleaner. Vorssaint требует macOS 14+ и Apple silicon, собирается через `swiftc` и распространяется под GPL-3.0-or-later; MacCleaner сохраняет собственную архитектуру, minimum target macOS 13, визуальную идентичность и самостоятельно проверенные реализации. Перед переносом любого кода необходимо отдельно оценить лицензионные последствия. Без такого решения допускается изучать публичное поведение, permission model, failure handling и архитектурные идеи, но реализацию писать самостоятельно.

## Внешний референс: Project Nullframe

[Project Nullframe](https://project-nullframe.vercel.app/) и его открытый репозиторий [m1ckc3s/nullframe](https://github.com/m1ckc3s/nullframe) использовать как ориентир для визуального языка телеметрии, dashboard-композиции и экономного обновления интерфейса. Это browser telemetry dashboard, а не macOS system utility, поэтому его источники данных и React-реализация не переносятся в MacCleaner напрямую.

Полезные паттерны для `IMP-007`, `IMP-036`, `IMP-037` и `IMP-054`:

- честно маркировать источник значения: измеренное `LIVE`, недоступное или демонстрационное `SIM`, а в MacCleaner предпочтительно `Unavailable`, если симуляция не нужна пользователю;
- использовать один координированный telemetry cadence и общий immutable snapshot вместо независимого таймера на каждый widget;
- полностью останавливать необязательные animation/render loops, когда интерфейс скрыт;
- не перерисовывать offscreen-графики и ограничивать частоту визуального render независимо от частоты критического sampler;
- собирать метрики в модульные bento cards с ясной иерархией primary value, unit, source/status и secondary context;
- применять dot-matrix/segmented gauges, моноширинные цифры и короткую motion feedback дозированно;
- сохранять command-palette подход и настройку motion, включая reduced-motion режим.

Что не следует копировать буквально:

- фирменный Nothing design language, шрифтовую и цветовую идентичность;
- browser fallback на seeded simulated telemetry в продуктовых системных экранах;
- React/Vite architecture вместо нативных SwiftUI/SystemMonitor слоёв;
- постоянную декоративную анимацию, если она увеличивает energy impact MacCleaner.

См. [README Project Nullframe](https://github.com/m1ckc3s/nullframe/blob/main/README.md), где описаны источники `LIVE/SIM`, единый `requestAnimationFrame` loop, публикация snapshot с меньшей частотой, пауза hidden-tab и пропуск offscreen canvas.

## 1. Floating Drop Shelf

Плавающая временная область появляется по shortcut, через menu bar или при drag к выбранному краю экрана. Она принимает изображения, текст, файлы, папки, URL и другие типы, которые можно безопасно представить через `NSItemProvider`/UTType.

Базовый сценарий:

1. пользователь перетаскивает один или несколько объектов;
2. shelf сохраняет ссылки или временные копии и показывает их тип, размер и источник;
3. пользователь перетаскивает элементы дальше, копирует текст, открывает файл либо запускает доступное действие;
4. временные данные очищаются вручную, по таймеру или после завершения сессии.

Требования безопасности:

- не перемещать исходный файл без явного выбора;
- различать bookmark/reference и физическую временную копию;
- показывать размер временного хранилища;
- не отправлять содержимое в сеть;
- не сохранять clipboard history по умолчанию;
- очищать security-scoped access и временные файлы после удаления карточки.

Shelf может стать точкой входа для сжатия изображения, OCR, получения цвета, Quick Look и последующего App Control, но эти действия должны оставаться отдельными и видимыми.

## 2. Микшер громкости приложений

Желаемый интерфейс показывает активные аудиоприложения, текущую активность, mute/solo и индивидуальный gain. Однако это не эквивалентно обычному изменению системной громкости.

Apple предоставляет Core Audio process taps для захвата вывода отдельного процесса или группы процессов. Tap умеет выбирать и mute-ить источник, но полноценное изменение громкости с возвратом аудио на устройство может потребовать собственного routing/aggregate-device контура и отдельного permission/lifecycle дизайна. Поэтому функция начинается с технического прототипа на поддерживаемых версиях macOS.

Этапы:

1. обнаружить аудиоактивные процессы;
2. проверить создание и стабильное уничтожение process tap;
3. реализовать mute и meter без утечки tap/aggregate device;
4. проверить регулируемый gain и вывод на исходное устройство;
5. только после этого проектировать постоянный mixer UI.

Нельзя обещать поддержку каждого приложения: DRM, эксклюзивные устройства, Bluetooth/AirPlay и смена output device требуют отдельного тестирования. При завершении MacCleaner исходный аудиомаршрут должен гарантированно восстанавливаться.

Официальная основа: [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).

## 3. Media Compressor

Первый scope — локальное сжатие изображений и анимированных GIF:

- JPEG: quality, metadata policy и progressive output;
- PNG: lossless optimization и optional resize;
- HEIC: quality/resize при системной поддержке;
- GIF: сохранение всех frames, frame duration, loop count и transparency;
- batch mode для нескольких файлов;
- сравнение исходного и итогового размера до сохранения.

Правила:

- исходник не перезаписывается по умолчанию;
- запись идёт во временный файл с последующим atomic move;
- пользователь видит формат, dimensions, frame count, metadata и ожидаемую экономию;
- увеличение размера считается неудачным результатом и явно показывается;
- удаление metadata — отдельная настройка, а не скрытый побочный эффект;
- для GIF нужен визуальный preview, чтобы выявлять потерю кадров, timing и transparency.

Видео можно рассматривать отдельным последующим этапом через AVFoundation, поскольку presets, HDR, audio tracks и длительность делают его существенно более сложным продуктом.

## 4. Homebrew Maintenance

MacCleaner должен выступать прозрачной оболочкой над установленным пользователем `brew`, а не устанавливать собственную копию Homebrew.

Безопасный поток:

1. найти фактический executable и показать его происхождение;
2. получить список formulae/casks и pinned state;
3. выполнить проверку outdated и показать план;
4. обновлять только выбранные пакеты после подтверждения;
5. сохранять stdout/stderr, exit status, duration и итоговую версию;
6. предлагать `cleanup --dry-run` до реальной очистки.

Автоматический `brew upgrade` в фоне по умолчанию недопустим: обновление может затронуть dependencies, сервисы и запущенные casks. Нужно поддерживать pins, исключения, отмену до начала мутации и понятное восстановление после частичной ошибки.

Официальная основа: Homebrew рекомендует последовательность `brew update`, `brew outdated`, затем выборочный или общий `brew upgrade`; pinned packages должны быть видимы отдельно. См. [Homebrew FAQ](https://docs.brew.sh/FAQ) и [brew manpage](https://docs.brew.sh/Manpage).

## 5. Пипетка цвета

Для основной функции достаточно нативного `NSColorSampler`, который показывает системный sampler и возвращает выбранный экранный цвет.

Результат:

- preview swatch;
- HEX, RGB, HSB и Display P3/sRGB representation;
- копирование выбранного формата;
- короткая локальная история, включаемая пользователем;
- предупреждение о color-space conversion, чтобы значение не выглядело абсолютно одинаковым во всех профилях дисплея.

Официальная основа: [`NSColorSampler`](https://developer.apple.com/documentation/appkit/nscolorsampler).

## 6. Копирование текста с экрана

Пользователь запускает shortcut, выбирает область, MacCleaner получает один кадр, выполняет локальный OCR через Vision и показывает результат до копирования.

Поток должен включать:

- системное объяснение Screen Recording permission;
- выбор display/window/region без постоянной фоновой записи;
- исключение окна MacCleaner из capture, где это возможно;
- выбор языков и режима fast/accurate;
- confidence и возможность убрать ошибочно распознанные строки;
- копирование только после preview;
- отсутствие сохранения screenshot по умолчанию.

ScreenCaptureKit предоставляет выбор и capture экранного содержимого, а `VNRecognizeTextRequest` выполняет локальное распознавание текста. См. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) и [`VNRecognizeTextRequest`](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).

## 7. Режимы предотвращения сна

Нужны отдельные профили, потому что «не выключать дисплей» и «не давать системе уснуть» — разные действия:

- Keep System Awake;
- Keep Display Awake;
- Presentation;
- While App Is Running;
- таймер 15/30/60 минут или до заданного времени;
- режим только при подключённом питании.

Реализация должна создавать именованный IOPM assertion с причиной и timeout, показывать активное состояние в menu bar и всегда освобождать assertion при выключении режима или завершении приложения. Power assertion — запрос системе, а не абсолютная гарантия: macOS может уснуть при критическом заряде или thermal emergency.

Официальная основа: [`IOPMAssertionCreateWithDescription`](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti) и [IOPM assertion types](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes).

## 8. Порог зарядки

Эта функция должна быть capability-gated.

Apple добавила пользовательский Charge Limit 80–100% для Apple silicon начиная с macOS Tahoe 26.4. Для текущего minimum target macOS 13 функция доступна не везде, а публичный API для изменения системного порога сторонним приложением не подтверждён.

Безопасный первый вариант:

- показать battery health, charge state и доступность системного Charge Limit;
- открыть соответствующий раздел System Settings и объяснить настройку;
- отображать выбранный системой limit, только если существует стабильный читаемый источник;
- не писать SMC/private keys и не устанавливать privileged helper ради этой функции;
- прямое управление добавлять только после появления документированного API или отдельно принятого hardware-specific решения с recovery plan.

Официальная основа: [About Optimized Battery Charging and Charge Limit on Mac](https://support.apple.com/en-au/102338).

## 9. Компактные индикаторы menu bar

Референс задаёт вертикальную композицию: слева stacked label `CPU`, `GPU` или `RAM`, справа узкий скруглённый gauge с цветным заполнением снизу. Для MacCleaner это следует оформить как выбираемые модули, а не жёстко заданный длинный label.

Предлагаемые модули:

- CPU gauge;
- GPU gauge, если достоверная метрика доступна;
- RAM gauge;
- temperature/status dot;
- battery/charge state;
- компактный или numeric режим по выбору.

Требования:

- одинаковая высота и baseline всех gauge;
- минимальная ширина и отсутствие эмодзи в основном варианте;
- semantic colors normal/warning/critical, а не только декоративная заливка;
- accessibility label с полными значениями;
- настройка порядка и скрытия модулей;
- сохранение существующего popover по клику;
- новый layout не должен повышать cadence `SystemMonitor` сам по себе;
- fallback для GPU `—` или скрытие, а не выдуманное значение.

Для первого прототипа достаточно CPU/RAM и optional GPU, используя уже существующий `SystemMonitor`. После визуального теста нужно проверить светлую/тёмную menu bar, разные wallpapers, notch, увеличенный accessibility contrast и ширину при трёх модулях.

## Предлагаемая группировка

- `Quick Shelf`: временные элементы и действия над ними.
- `Capture Tools`: цвет и OCR.
- `Media`: изображения и GIF.
- `System Tools`: Homebrew, awake profiles и battery capability.
- `Menu Bar`: компактные gauges и быстрые переключатели.

## Предлагаемый порядок

1. Пипетка и OCR как небольшие изолированные инструменты.
2. Awake profiles с корректным release lifecycle.
3. Menu bar gauges на существующих метриках.
4. Floating Drop Shelf как общая точка входа.
5. Media Compressor с transactional output.
6. Homebrew read-only audit, затем подтверждаемые upgrades.
7. Audio mixer prototype.
8. Charge Limit только в пределах подтверждённых системных возможностей.

## Связанные материалы

- [[Architecture]]
- [[Features]]
- [[Opportunities]]
- [Vorssaint Utils](https://github.com/vorssaint/vorssaint-utils)
- [Project Nullframe](https://project-nullframe.vercel.app/)
- [Project Nullframe source](https://github.com/m1ckc3s/nullframe)
