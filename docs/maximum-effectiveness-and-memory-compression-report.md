# MacCleaner: предел эффективности и сжатая память macOS

Дата: 2026-07-13
Commit: `c935a8e`
Стенд: MacBook Pro 14-inch, Apple M3 Pro, 18 GiB unified memory, macOS 26.1

## Итог

Текущая эффективность MacCleaner не является максимально достижимой. Однако главный резерв находится не в принудительном освобождении RAM, а в более точной диагностике, корректном выборе момента вмешательства и измерении результата после действия.

На проверенном Mac macOS уже выполняет очень эффективное автоматическое управление памятью:

- около 13.27 GiB исходных страниц находились в compressor;
- compressor занимал около 4.08 GiB физической RAM;
- фактическое сжатие составляло примерно 3.25:1;
- экономия физической памяти составляла около 9.19 GiB;
- за 10-секундное окно не было новых compressions, swap-ins или swap-outs;
- `memory_pressure` сообщал 54% system-wide free percentage;
- swap содержал 1.65 GiB исторически выгруженных данных, но текущая swap-активность была нулевой.

В таком состоянии освобождение нескольких гигабайт ради увеличения числа `Free RAM` почти наверняка не даст измеримого ускорения. Apple прямо указывает, что наличие большего объёма неиспользуемой памяти само по себе не улучшает производительность: главным индикатором является Memory Pressure, а cached memory используется для ускорения повторного открытия приложений. См. [Activity Monitor: memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac) и [Apple: check whether a Mac needs more RAM](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/mac).

## Ответ на главный вопрос

### Является ли текущий результат максимумом?

Нет.

Но нужно различать три максимума:

1. **Максимум числа Free RAM.** Его можно искусственно увеличить закрытием приложений или purge cache, но это слабая и часто вредная цель.
2. **Максимум производительности.** Он достигается минимизацией sustained memory pressure, swap I/O, page faults и latency реального workload, а не максимизацией свободной памяти.
3. **Максимум безопасной автоматизации.** MacCleaner не может решать за пользователя, какие приложения с несохранёнными данными закрывать. Поэтому безопасный автоматический предел ниже теоретически освобождаемого объёма.

Текущий MacCleaner оптимизирует главным образом первый показатель на уровне рекомендаций, но ещё не измеряет второй.

### Можно ли сделать лучше?

Да, существенно лучше по качеству решения и доказательности результата:

- использовать реальный system memory pressure вместо процента занятой RAM;
- измерять текущие rates compression, decompression, swap-in и swap-out;
- отличать private physical footprint от RSS и shared memory;
- определять memory-heavy idle applications и вероятные leaks;
- вмешиваться только при sustained warning/critical pressure или измеримом swap churn;
- после Quit повторно измерять pressure, footprint, compressor и swap rates;
- показывать отрицательные результаты: приложение закрыто, но pressure не улучшился; cache потерян; повторный запуск стал медленнее.

Apple предоставляет системный источник событий `normal`, `warning` и `critical` через [DispatchSourceMemoryPressure](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure). Для более точной оценки процесса доступны `phys_footprint`, `compressed` и связанные поля в [task_vm_info_data_t](https://developer.apple.com/documentation/kernel/task_vm_info_data_t).

## Что macOS делает автоматически

### Compressed memory

Когда системе становится тесно, неактивные страницы приложений сжимаются и остаются в RAM. Это дешевле, чем сразу записывать их на SSD. При повторном обращении страница распаковывается; если давление продолжает расти, часть данных может перейти в swap.

Apple описывает compressed memory как память, сжатую для освобождения RAM активным приложениям. Cached files также не являются потерянной памятью: система может быстро переиспользовать их, но до этого cache ускоряет повторный доступ.

Результат текущего snapshot:

| Метрика | Значение |
| --- | ---: |
| Physical memory | 18.00 GiB |
| Pages stored in compressor | 869,847 |
| Physical pages occupied by compressor | 267,656 |
| Logical content represented by compressor | 13.27 GiB |
| Physical compressor storage | 4.08 GiB |
| Compression ratio | 3.25:1 |
| Estimated physical RAM saved | 9.19 GiB |
| Inactive + speculative pages | 4.67 GiB |
| Purgeable pages | 0.19 GiB |
| Swap used | 1.65 GiB |
| Swap-ins during 10 s sample | 0 |
| Swap-outs during 10 s sample | 0 |
| New compressions during 10 s sample | 0 |

Эти величины нельзя просто сложить и назвать `freeable`: категории пересекаются по смыслу и управляются динамически. Главное наблюдение — система не выполняла активный swap или compression churn в измеренном окне.

### Почему 4.08 GiB compressed — не проблема

Compressed memory означает, что kernel уже нашёл компромисс между скоростью и ёмкостью. Удалять её как cache нельзя. Возможны только три естественных исхода:

1. страницы распакуются, когда приложение снова обратится к ним;
2. страницы будут освобождены после завершения owning process;
3. при дальнейшем pressure часть страниц перейдёт в swap.

Принудительный `purge` не является улучшением compressor. Он выбрасывает переиспользуемые file caches, после чего данные приходится читать или вычислять повторно.

## Ограничения текущего RAM Cleaner

### 1. Неверный индикатор pressure

MacCleaner рассчитывает:

```text
used = wired + active + physical compressed storage
usedPercent = used / total
```

Затем он присваивает состояние:

- более 60% — Moderate;
- более 75% — High;
- более 90% — Critical.

Это не macOS Memory Pressure. Apple учитывает совокупность free memory, swap rate, wired memory и file cache. На тестовом Mac формула MacCleaner давала около 70% used и статус Moderate, хотя текущие swap/compression rates были нулевыми и `memory_pressure` показывал значительный резерв.

Следствие: приложение может рекомендовать RAM cleanup в ситуации, когда macOS работает нормально.

### 2. `5.5 GB freeable` — верхняя оценка, не результат

MacCleaner:

1. агрегирует RSS всего process tree пользовательского приложения;
2. выбирает до десяти приложений тяжелее адаптивного threshold;
3. складывает их RSS;
4. после graceful Quit считает прежний RSS `estimatedReleasedBytes`;
5. не измеряет system pressure или память после завершения.

Почему фактически освобождённый объём будет меньше или просто другим:

- RSS разных процессов может включать shared pages;
- часть file-backed pages перейдёт в cache, а не в визуально свободную RAM;
- compressor и kernel перераспределят память асинхронно;
- другие приложения немедленно займут освободившуюся память;
- завершение одного процесса может не завершить все helper processes;
- закрытое приложение придётся запускать заново, создавая CPU, I/O и latency cost.

Поэтому строгая граница имеет вид:

```text
0 <= immediate physical capacity released <= summed candidate RSS
```

Для показанных 5.5 GB верхняя граница равна 5.5 GB, но доказанного нижнего результата выше нуля сейчас нет.

### 3. Текущий алгоритм не связывает действие с производительностью

Он не измеряет:

- normal/warning/critical pressure до и после;
- swap-in/swap-out rate;
- decompression rate;
- page-fault latency;
- `phys_footprint` и compressed footprint каждого приложения;
- latency foreground workload;
- время и ресурсы повторного запуска закрытого приложения.

Без этого нельзя ответить, стал ли Mac быстрее.

## Реалистичный максимум на текущем Mac

### В текущем спокойном состоянии

Измеренный максимум полезного ускорения от RAM cleanup близок к нулю по имеющимся доказательствам:

- pressure не показал активной аварийной ситуации;
- swap rate был нулевым;
- compression rate был нулевым;
- macOS уже сэкономила около 9.19 GiB благодаря compressor;
- закрытие приложений добавит reopen cost.

Можно освободить физическую ёмкость под будущий тяжёлый workload, но это профилактический reserve, а не текущее ускорение.

### Под реальной длительной нагрузкой

Потенциальный эффект может быть существенным, если одновременно выполняются условия:

- pressure устойчиво warning или critical;
- есть повторяющиеся swap-outs и swap-ins;
- foreground workload показывает latency degradation;
- найдено неиспользуемое приложение с большим private/compressed footprint;
- после его завершения pressure и latency действительно улучшаются.

В таком случае максимум ограничен private + compressed footprint закрываемого приложения, но оценивать его нужно по before/after, а не по исходному RSS.

## Как должна выглядеть улучшенная версия

### Приоритет 0: правильная модель памяти

Заменить `usedPercent` как pressure indicator на:

- `DispatchSource.makeMemoryPressureSource` для normal/warning/critical;
- rolling deltas swap-ins, swap-outs, compressions и decompressions;
- inactive, purgeable, compressor physical storage;
- системный pressure state и длительность состояния.

### Приоритет 1: точный footprint процессов

Для каждого приложения показывать отдельно:

- private physical footprint;
- compressed footprint;
- shared/file-backed footprint;
- child-process footprint;
- idle time;
- CPU usage;
- вероятность автоматического восстановления окон/processes.

RSS оставить диагностическим полем, но не использовать как обещанный объём освобождения.

### Приоритет 2: outcome-based recommendation

Рекомендовать Quit только когда:

```text
sustained pressure >= warning
AND candidate is idle
AND private/compressed footprint is material
AND app is not protected
AND user explicitly selects it
```

При normal pressure выводить: `macOS is managing memory efficiently; no cleanup is recommended`.

### Приоритет 3: измерение после действия

Снять samples в моменты:

- T−10 s baseline;
- непосредственно перед Quit;
- T+5 s;
- T+30 s;
- T+120 s;
- после повторного запуска приложения.

Final Report должен содержать:

| Метрика | До | После | Дельта |
| --- | ---: | ---: | ---: |
| Memory pressure state | — | — | improved / unchanged / worse |
| Candidate phys footprint | — | — | GiB |
| Compressor physical storage | — | — | GiB |
| Swap-in rate | — | — | pages/s |
| Swap-out rate | — | — | pages/s |
| Foreground workload p95 latency | — | — | ms |
| App reopen time | — | — | s |

Если pressure не улучшился, результат обязан быть показан как `No measurable system benefit`.

## Оценка достижимого улучшения продукта

| Направление | Сейчас | Потенциал |
| --- | --- | --- |
| Определение pressure | Процент used RAM | Большое улучшение: использовать системные events и rates |
| Оценка приложений | Сумма RSS process tree | Большое улучшение: private/phys/compressed footprint |
| Автоматическая рекомендация | Top apps выше threshold | Большое улучшение: pressure + idle + footprint + user context |
| Измерение результата | Estimated prior RSS | Критическое улучшение: реальный before/after |
| Работа с compressed memory | Только informational row | Трогать не нужно; macOS уже управляет ей эффективно |
| Производительность | Не измеряется | Измерять workload latency и swap churn |
| Отрицательные эффекты | Почти не измеряются | Добавить reopen cost, cache loss и unchanged/worse outcome |

## Финальный вердикт

1. **Нет, текущий результат не является максимальным.** Диагностику и доказательность можно улучшить значительно.
2. **Да, macOS уже автоматически сжимает память очень эффективно.** В snapshot она упаковала около 13.27 GiB страниц в 4.08 GiB, сэкономив около 9.19 GiB RAM.
3. **MacCleaner не должен пытаться конкурировать с compressor.** Безопасная роль приложения — объяснить состояние и предложить закрыть конкретное неиспользуемое приложение только при реальном pressure.
4. **Показанные 5.5 GB нельзя называть достижимым освобождением.** Это верхняя RSS-оценка; реальный эффект не измерен.
5. **В текущем состоянии Mac доказательств ускорения от RAM cleanup нет.** Swap/compression churn отсутствовал, поэтому наиболее правильное действие — ничего не закрывать.
6. **Лучший достижимый продуктовый результат — не максимум Free RAM, а снижение sustained pressure и latency при минимальной цене для пользователя.**
