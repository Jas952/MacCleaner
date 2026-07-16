# MacCleaner: измерение фактической эффективности

Дополнительный анализ предельной эффективности RAM и работы compressor: [maximum-effectiveness-and-memory-compression-report.md](./maximum-effectiveness-and-memory-compression-report.md).

Дата измерения: 2026-07-13
Commit: `c935a8e` (`main`, продуктовая версия 1.2)
Стенд: MacBook Pro 14-inch, Apple M3 Pro, 18 GB RAM, macOS 26.1
Сборка: Release, arm64, Xcode SDK 26.2, `CODE_SIGNING_ALLOWED=NO`

## Короткий вывод

Текущий раздел `Measured Results` в README в основном измерял изменения реализации: интервалы опроса, лимиты скана и наличие safety-тестов. Это полезные regression-метрики, но они не отвечают на главный продуктовый вопрос: что именно улучшилось на Mac после действия пользователя.

Проведённые проверки дали три фактических результата:

1. Очистка через Trash на 100% убирает выбранный объект из исходного места, но до очистки Корзины практически не возвращает свободное место на диске.
2. Optimize действительно находит кандидатов, но показанные `1.2 GB` означают оценённый объём для перемещения в Корзину, а `5.5 GB RAM` — верхнюю оценку памяти приложений для ручного закрытия. Это не измеренный результат после действия.
3. MacCleaner не выполняет автоматическое охлаждение. Открытый Dashboard сам создаёт небольшую измеримую нагрузку, поэтому температурный эффект нельзя считать положительным без отдельного A/B-теста ручного управления вентиляторами.

## Решение по Optimize: Lite / Efficient и Pro / Thorough

### Что реально работает сейчас

Пользовательские режимы `Professional` и `Optimization` не переключают глубину сканирования. One-click `Optimize` вызывает `DiskCleaner.scan` без параметра, поэтому всегда получает режим `.efficient` по умолчанию. Отдельный disk scan также запускается через `startScan()` с тем же default. В рабочем UI не найдено ни одного вызова `.thorough`.

Следовательно, фактического сравнения `Optimize Lite` и `Optimize Pro` в текущем продукте нет: оба пользовательских пути используют один быстрый алгоритм, а `Thorough` существует только как бюджет в коде и в тестах.

| Показатель | Lite / Efficient | Pro / Thorough |
| --- | ---: | ---: |
| Реально вызывается из Optimize | Да | Нет |
| Общий лимит записей | 80,000 | 500,000 |
| Общий лимит времени | 12 s | 60 s |
| Лимит записей на root | 5,000 | 50,000 |
| Лимит времени на root | 0.45 s | 3 s |
| Измеренный результат на тестовом Mac | Review примерно за 2.5 s; найдено 1.2 GB кандидатов | Не измерим как продуктовая функция: путь недоступен пользователю |
| Доказанный дополнительный эффект Pro | — | 0 в текущем UI |

Большие лимиты Thorough означают только потенциально больший охват: до 6.25 раза больше записей, в 5 раз больше общего времени и до 10 раз больше записей на root. Они сами по себе не доказывают ни больший объём полезной очистки, ни лучшую эффективность. Текущий тест проверяет лишь различие лимитов, а не recall, найденные bytes, CPU, I/O или итоговый reclaimed space.

### Насколько эффективен Lite

Lite / Efficient эффективен как быстрый безопасный triage:

- на этом Mac дошёл до Review примерно за 2.5 секунды;
- нашёл 1.2 GB кандидатов для Trash;
- не закрывает приложения автоматически и сообщает о частичном результате при достижении лимита;
- ограничивает время и объём обхода, поэтому подходит как default.

Но его эффективность как оптимизатора системы не доказана:

- 1.2 GB — это найденные кандидаты, не уже освобождённое место;
- при Trash-only очистке тестового файла 256 MiB немедленно вернулось практически 0 bytes;
- показанные 5.5 GB RAM — верхняя RSS-оценка для ручного review;
- при здоровом memory pressure ожидаемое ускорение от закрытия приложений близко к нулю;
- влияние maintenance и DNS на реальную latency не измеряется.

### Насколько эффективен Pro

Как пользовательская возможность Pro / Thorough сейчас неэффективен: код глубокой проверки не подключён к Optimize или видимым кнопкам скана. Поэтому пользователь получает тот же Efficient scan, а прирост качества Pro равен нулю независимо от более высоких теоретических лимитов.

Подключать полный Thorough scan как новый default не следует. Более разумная схема:

1. всегда запускать быстрый Efficient scan;
2. если `wasLimited == true`, предлагать продолжить Deep scan;
3. углублять только roots, на которых был достигнут лимит;
4. показывать дополнительный результат отдельно: `+bytes`, `+items`, дополнительное время, CPU и I/O;
5. сохранять Thorough как явный Pro-инструмент, а не как скрытое обещание тарифа.

### Критерий, стоит ли менять алгоритм

Основную безопасную механику менять не нужно: bounded scan, ручной review, Trash-only и отказ от автоматического Quit являются правильными решениями. Нужна точечная доработка маршрутизации режимов и измерения результата.

Рекомендуемый продуктовый gate для парного теста на одинаковом corpus:

- если Thorough даёт менее 10–15% дополнительных корректных reclaimable bytes при цене более 3x по времени или I/O, оставлять его только диагностическим инструментом;
- если он стабильно даёт более 20% дополнительных корректных bytes на целевой аудитории при приемлемом времени, показывать его как явный Deep/Pro scan;
- при любом результате не считать bytes в Trash уже освобождённым местом и не считать RSS гарантированно освобождённой RAM.

Эти пороги являются предлагаемым продуктовым решением, а не уже измеренным свойством текущей версии.

## Что было реально проверено

### 1. Автоматические тесты

Команда:

```bash
xcodebuild test \
  -project MacCleaner.xcodeproj \
  -scheme MacCleaner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/TestDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Результат из `xcresult`:

| Метрика | Результат |
| --- | ---: |
| Всего тестов | 39 |
| Passed | 39 |
| Failed | 0 |
| Skipped | 0 |
| Время test operation | 4.364 s |

Это подтверждает regression barrier для safety/policy. Тесты не доказывают, что после Optimize стало больше свободного места, меньше memory pressure или ниже температура.

### 2. Реальный результат Optimize scan

Release-приложение было открыто на этом Mac, затем в UI выполнен только read-only scan. Кнопка cleanup не нажималась.

| Наблюдение | Результат | Честная интерпретация |
| --- | ---: | --- |
| Время до состояния Review | около 2.5 s | End-to-end время UI-автоматизации; не изолированное время алгоритма |
| Disk | 1.2 GB | Оценка выбранных кандидатов для Trash, не уже освобождённое место |
| RAM | 5.5 GB | Суммарная оценка RSS приложений для ручного review, не гарантированно освобождённая RAM |
| System | 4 tasks | Число подготовленных maintenance-действий, не доказанное ускорение системы |
| DNS | cache | Подготовлен flush; влияние на latency не измерено |

Скан был намеренно остановлен на Review: найденные пользовательские данные не удалялись и приложения не закрывались.

### 3. Очистка диска через Trash

Для проверки семантики cleanup был создан отдельный непрерывный файл размером 256 MiB. Измерение доступного места выполнялось после `sync`, до и после перемещения файла в пользовательскую Корзину. Затем файл был возвращён, удалён и отсутствие изменений в Git проверено.

| Метрика | До Trash | После Trash | Дельта |
| --- | ---: | ---: | ---: |
| Файл в исходном месте | 256 MiB | 0 | −256 MiB |
| Файл в Корзине | 0 | 256 MiB | +256 MiB |
| Available space | 164,949,788 KiB | 164,949,796 KiB | +8 KiB |
| Реально возвращено ёмкости | — | — | ≈0.003% от размера файла, то есть шум |

После настоящего удаления тестового файла available space вырос примерно на 259 MiB; небольшое отличие от 256 MiB объясняется APFS и параллельной активностью системы.

Вывод: значение, которое код называет `freed`, фактически является `measured bytes moved to Trash`. Пока Корзина не очищена, корректная метрика `disk space reclaimed` равна примерно нулю. Это не ошибка Trash-only safety policy, но UI и отчёты должны использовать точный термин.

### 4. Нагрузка самого приложения

Release-приложение измерялось после 5 секунд прогрева: 20 выборок `top` с интервалом 2 секунды, Dashboard был открыт.

| Метрика | Результат |
| --- | ---: |
| CPU median | 1.4% одного CPU core |
| CPU average | 2.9% одного CPU core |
| CPU peak | 24.2% одного CPU core |
| Resident memory, обычно | 52–54 MiB |
| Resident memory, peak | 62 MiB |
| Threads | 4–6 |
| CPU time за окно около 40 s | +1.24 s |
| Context switches за окно | +1,204, около 30/s |
| Page-ins за окно | +1 |

Пики совпадают по порядку времени с обновлениями активного экрана. Эти цифры не являются energy score, но показывают, что мониторинг имеет собственную ненулевую стоимость.

Текущая Release-сборка занимает 34,872 KiB, главный executable — 31,630,184 bytes.

### 5. Температура и вентиляторы

В момент проверки Fans screen показывал:

| Метрика | Наблюдение |
| --- | ---: |
| Fans | 2, оба Auto |
| Активные temperature sensors | 23 |
| CPU | 52 °C |
| SoC | 50 °C |
| Battery | 31 °C |
| SSD | данных нет |

Это snapshot состояния, а не результат охлаждения. MacCleaner в этом сценарии ничего не менял: вентиляторы оставались в Auto. Следовательно, измеренный автоматический cooling effect равен `not applicable`; утверждать снижение температуры нельзя.

Ручной fan-control A/B-тест в эту проверку не включён. Он требует изменения системного состояния, фиксированной нагрузки, одинаковой ambient temperature и контроля шума/питания. Без этого разница температуры будет смешана с фоновой нагрузкой других процессов.

## Метрики эффективности, которые реально можно получить

Ниже перечислены не только положительные, но и отрицательные результаты. Значение дельты всегда должно сохранять знак.

### Disk cleanup

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| Selected bytes | Сумма allocated bytes выбранных объектов | Есть как оценка |
| Successfully moved bytes | Сумма размера только успешно trashed объектов | Есть, но названа `freed` |
| Move success rate | `successfully moved items / attempted items` | Можно добавить без новых прав |
| Byte success rate | `moved bytes / selected bytes` | Можно добавить без новых прав |
| Actual disk reclaimed | `available_after - available_before` | Нужно измерять до/после; до Empty Trash ожидается около 0 |
| Reclaimed after Empty Trash | Дельта available после явной очистки Корзины | Реальна, но требует отдельного подтверждённого действия пользователя |
| Estimation error | `(reported moved bytes - actual allocated bytes) / actual allocated bytes` | Можно измерить на fixtures |
| Cleanup duration | От подтверждения до completion | Можно добавить |
| Cleanup throughput | `successfully moved bytes / duration` | Можно добавить |
| Error count/rate | Ошибки Trash, permissions, changed/missing files | Частично уже возвращается |
| Cache regrowth | Размер тех же путей через 5 min / 1 h / 24 h | Нужен longitudinal test |
| Net 24h disk benefit | `reclaimed - regrown bytes` | Нужен longitudinal test |
| Redownload cost | Network bytes после очистки cache | Нужен A/B network trace |
| Cold-start penalty | Время запуска приложения до/после очистки его cache | Нужен A/B benchmark; дельта может быть отрицательной |

### Scan quality

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| Scan duration | Start-to-result monotonic clock | Можно добавить |
| Entries visited | Уже есть `scannedEntryCount` для части scan flows | Частично есть |
| Stop reason | Completed / deadline / entry cap / cancelled / permission | Частично есть, следует унифицировать |
| Coverage | `visited fixture entries / total fixture entries` | Нужен synthetic corpus |
| Byte recall | `found reclaimable bytes / known reclaimable bytes` | Нужен synthetic corpus |
| False-positive rate | Небезопасные/нужные bytes среди рекомендаций | Нужна разметка и fixtures |
| Permission undercount | Разница Full Disk Access on/off | Нужен парный запуск |
| Efficient vs Thorough gain | Дополнительные найденные bytes / дополнительное время и CPU | Можно измерить парным scan |

### RAM review

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| Estimated releasable RSS | Сумма RSS выбранных приложений | Есть, но это upper bound |
| Apps asked to quit | Count | Можно добавить |
| Apps actually exited | Count + PID verification | Частично есть |
| Refusal rate | `remained open / requested` | Частично есть |
| Actual RSS removed | Сумма final RSS исчезнувших PIDs | Можно измерить |
| System available-memory delta | До/через 5/30/120 s после quit | Можно измерить, сильно шумит |
| Memory-pressure delta | macOS pressure level до/после | Следует добавить; полезнее free RAM |
| Swap delta | swap used/pages before/after | Можно измерить |
| Reopen cost | Время, CPU и I/O на возврат закрытых приложений | Нужен A/B test; отрицательный эффект обязателен |
| Unsaved-work incidents | Count | Нельзя надёжно автоматизировать; нужен user report |

### Thermal and fans

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| Temperature snapshot | CPU/SoC/battery/SSD | Есть, hardware-dependent |
| Peak temperature | Max за фиксированную нагрузку | Можно измерить на поддерживаемом Mac |
| Time to cool | Время, например, от 90 °C до 60 °C | Нужен контролируемый workload |
| Cooling slope | °C/min после снятия нагрузки | Нужен контролируемый workload |
| Thermal pressure | nominal/fair/serious/critical over time | Следует добавить |
| Fan RPM delta | Manual minus Auto | Есть только при поддержке hardware/control |
| Performance retained | Benchmark throughput/clock under equal workload | Нужен A/B benchmark |
| Acoustic cost | dBA at fixed distance | Нужен внешний calibrated sensor |
| Power/battery cost | W или battery discharge rate | Нужны powermetrics/admin или внешний meter |
| App-induced thermal cost | Температура/energy MacCleaner idle vs not running | Нужен длительный randomized A/B test |

Автоматический cooling score сейчас публиковать нельзя: приложение не включает manual fan mode само и не выполняет workload-controlled experiment.

### Maintenance, DNS and startup

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| Task success rate | Successful maintenance tasks / attempted | Можно добавить |
| Task duration | Per-task monotonic duration | Можно добавить |
| DNS latency delta | Median/p95 lookup latency до/после flush | Можно измерить; улучшение не гарантировано |
| First DNS lookup penalty | Первый lookup после flush | Нужно учитывать как возможный минус |
| Login-time delta | Median login-to-idle across several reboots before/after startup disable | Нужны повторные reboot sessions |
| Post-login CPU/RSS | Aggregate at T+30/60/120 s | Нужны повторные sessions |
| Restore success rate | Disabled item restored and launches normally | Можно тестировать на fixtures; реальные items требуют осторожности |

### Uninstall, duplicates, similar photos and cloud reclaim

| Метрика | Формула / способ | Доступность сейчас |
| --- | --- | --- |
| App + leftovers moved | Bytes and item count successfully trashed | Можно добавить |
| Leftover coverage | Found known leftovers / fixture leftovers | Нужен synthetic app fixture |
| Duplicate precision | Hash-confirmed duplicate groups / proposed groups | SHA-256 path уже позволяет измерить |
| Duplicate byte recall | Found reclaimable duplicate bytes / known fixture bytes | Нужен corpus |
| Similar-photo precision/recall | По размеченному набору пар | Нужен labeled image corpus |
| Cloud local bytes evicted | Available-space delta after eviction | Можно измерить на controlled cloud fixtures |
| Cloud redownload penalty | Latency + network bytes при повторном открытии | Нужен A/B test |
| False destructive outcomes | Changed file, wrong cloud state, last copy removed | Safety tests есть; нужен zero-tolerance counter |

## Что следует показывать пользователю после Optimize

Минимальный честный Final Report:

1. `Moved to Trash`: bytes/items.
2. `Disk space reclaimed now`: available-space delta; обычно около нуля до Empty Trash.
3. `Potential reclaim after Empty Trash`: bytes в успешно перемещённых объектах.
4. `Apps closed / refused`: count.
5. `Measured RSS removed`: исчезнувший RSS выбранных PIDs, отдельно от system available-memory delta.
6. `Maintenance tasks succeeded / failed`: count и duration.
7. `Temperature effect`: показывать только если было реальное fan-control действие и достаточно before/after samples; иначе `Monitoring only — no cooling action applied`.
8. `MacCleaner cost during operation`: duration, average/peak CPU, peak RSS.

Не следует складывать disk bytes, RAM bytes, число tasks и температуру в единый synthetic cleaner score: это разные единицы, разные временные горизонты и разная причинность.

## Итоговая оценка текущей версии

| Область | Что доказано | Что не доказано |
| --- | --- | --- |
| Safety | 39/39 tests, Trash-only semantics | Нулевая вероятность ошибки на любых реальных данных |
| Disk | Кандидаты находятся; выбранный объект перемещается в Trash | Немедленное освобождение показанных bytes |
| RAM | Находятся приложения для ручного review | Что показанные 5.5 GB реально освободятся |
| Maintenance | Формируются 4 задачи | Что Mac становится быстрее после их выполнения |
| DNS | Flush доступен | Что latency улучшится; первый lookup может стать медленнее |
| Cooling | Температуры и fans читаются на этом Mac | Автоматическое снижение температуры |
| App efficiency | Измерены CPU/RSS и пики Dashboard | Energy impact и длительный температурный эффект |

Главное изменение терминологии: `freed` в текущем Trash-only cleanup следует трактовать и отображать как `moved to Trash`; реальную эффективность нужно считать по before/after состоянию системы.
