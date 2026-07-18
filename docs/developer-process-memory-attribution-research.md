# Developer Process & Memory Attribution

## Продуктовая гипотеза

MacCleaner может выделиться не ещё одним списком процессов, а режимом **Developer Memory Intelligence**: показывать, какой workspace, агент, IDE, language server, build/watch tool, runtime, контейнер, MCP-сервер или локальный индекс сформировали нагрузку и на каких доказательствах основан вывод.

Целевой ответ продукта — не только «процесс занял 4 GB», а, например: «во время сессии агента в этом workspace выросли три Node-потомка; основной вклад дал language server, рост продолжался после завершения задачи; связь подтверждена parent/child PID и временем жизни, причина внутри heap пока не профилировалась».

## Фактическая основа MacCleaner

- `SystemMonitor` уже получает total, free, wired, active, compressed, inactive и speculative memory через Mach host statistics. Текущий `used` складывается из wired, active и compressed.
- `ProcessTreeService` уже получает PID, parent PID, CPU и память и строит дерево процессов.
- `ProcessDetailService` показывает parent chain, descendants и число открытых файлов.
- `AIWorkloadService` уже группирует основной процесс агента, descendants, MCP, helpers и terminal tools для Codex, Hermes, Antigravity, Devin, Claude Code, Cursor, Aider, Goose и Continue.

Этого достаточно для read-only baseline, но недостаточно для точного объяснения причины заполненности памяти: одного RSS и одновременного запуска процессов недостаточно.

## Что означает «точечно определить причину»

Нужно разделять три уровня ответа:

1. **Системное состояние** — memory pressure, compressed memory, swap activity, wired memory и cache. Высокая занятость RAM сама по себе не означает проблему.
2. **Вклад workload** — изменение памяти группы процессов относительно baseline, slope роста, peak, время жизни и связь с developer-session.
3. **Причина внутри runtime** — allocation stacks, heap dominators, retainers, объекты или handles. Такой ответ возможен только через opt-in profiler конкретного runtime.

MacCleaner не должен утверждать, что один PID «заполнил память», если видна только корреляция. Shared memory, cache и уже работавшие общие сервисы показываются отдельно.

## Репозитории для исследования

| Репозиторий | Что изучить | Граница применения |
| --- | --- | --- |
| [exelban/stats](https://github.com/exelban/stats) | Нативный сбор CPU/GPU/memory/disk/network/sensors, модульность collectors и явную стоимость отдельных модулей | Не копировать UI и не считать общесистемные метрики per-process причиной |
| [aristocratos/btop](https://github.com/aristocratos/btop) | Process tree, фильтрацию, сортировку и быстрое исследование большого списка процессов | Это системный монитор, а не модель developer-workload |
| [nicolargo/glances](https://github.com/nicolargo/glances) | Plugin/export architecture, историю метрик и read-only MCP-доступ к системной наблюдаемости | Не переносить Python runtime как обязательную зависимость macOS-приложения |
| [tlkh/asitop](https://github.com/tlkh/asitop) | Источники Apple silicon telemetry: `powermetrics`, P/E clusters, GPU/ANE, memory и swap | Требует повышенных прав; часть mapping зависит от версии macOS и не годится как безусловная гарантия |
| [giampaolo/psutil](https://github.com/giampaolo/psutil) | Матрицу доступных process/system метрик и семантику cross-platform API | Использовать как checklist, а не добавлять Python-зависимость |
| [osquery/osquery](https://github.com/osquery/osquery) | Query/evidence model для процессов, соединений, launchd и расширяемых таблиц | Не встраивать тяжёлый daemon без отдельного overhead и security-аудита |
| [bloomberg/memray](https://github.com/bloomberg/memray) | Python allocation/native stacks, flame graph, tree и поиск leaks/high-watermark | Только явный opt-in adapter для Python-сценария; не запускать profiler скрытно |
| [facebook/memlab](https://github.com/facebook/memlab) | Heap snapshots, dominators/retainers и MCP-сценарий AI-assisted анализа JS/Node/Electron/Hermes | Heap snapshot может содержать чувствительные данные; нужен preview, scope и retention policy |
| [mafintosh/why-is-node-running](https://github.com/mafintosh/why-is-node-running) | Объяснение, какие Node handles удерживают процесс после завершения задачи | Отвечает на lifecycle/handles, но не заменяет анализ heap и system pressure |
| [clinicjs/node-clinic](https://github.com/clinicjs/node-clinic) | UX автоматической диагностики, flame/heap reports и рекомендации | Репозиторий не поддерживается активно; использовать только как исторический design reference |

Особенно важны два сигнала рынка: Glances даёт MCP-интерфейс к системным метрикам, а MemLab — MCP-интерфейс к heap-анализу. MacCleaner может объединить оба уровня локально и связать их с уже существующей моделью AI-агентов.

## Предлагаемая модель Developer Workload Graph

### Узлы

- developer session и workspace;
- AI agent и IDE;
- process и executable;
- language server, compiler, build/watch tool и runtime;
- MCP server, local utility, container и indexer;
- memory sample, system-pressure event и profiler report.

### Связи и уровень доказательства

- `observed` — parent/child PID, executable path, launch/exit, открытый файл или endpoint;
- `configured` — tool, MCP или executable явно указан в конфигурации;
- `profiled` — причина подтверждена profiler report;
- `inferred` — совпадение workspace, имени или времени без прямой связи.

Каждое ребро хранит timestamp, источник и confidence. Командные строки, пути и окружение должны проходить redaction до записи или экспорта.

## Три режима диагностики

### 1. Quick Baseline

Read-only snapshot без инъекций и admin-доступа: system pressure, compressed/swap, top process groups, descendants, lifetime и отклонение от baseline.

### 2. Developer Session Recording

Явно включаемая запись выбранного workspace или агента: slope и peak памяти, появление/исчезновение процессов, вклад группы, события build/index/test/MCP и сравнение с предыдущей сессией.

### 3. Deep Runtime Profile

Отдельное подтверждаемое действие. Адаптер либо запускает тестовую команду под profiler в изолированном workspace, либо импортирует уже созданный report. Первая очередь кандидатов:

- Python — Memray report;
- JavaScript/Node/Electron/Hermes — heap snapshot + MemLab;
- Node lifecycle — `why-is-node-running` report.

Автоматическое подключение profiler к произвольному рабочему процессу, скрытая инъекция и чтение heap без согласия недопустимы.

## Формат пользовательского вывода

Для каждого вывода показывать:

- что изменилось относительно baseline;
- какой workload или компонент внёс вклад;
- тип доказательства и confidence;
- что остаётся shared/unknown;
- безопасное обратимое действие: остановить watcher, перезапустить language server, закрыть idle agent session, уменьшить concurrency или открыть profiler report;
- ожидаемый эффект и способ проверить результат.

Terminate и force-terminate остаются отдельными подтверждаемыми действиями. Рекомендация не должна автоматически завершать процессы.

## Privacy, permissions и стоимость наблюдения

- local-first хранение с видимым retention и полным удалением;
- redaction токенов, query strings, home paths, командных секретов и содержимого файлов;
- heap/profile reports не экспортируются без явного выбора;
- read-only MCP/API по умолчанию не предоставляет destructive tools;
- каждый collector имеет измеренный sampling interval, CPU/RSS overhead и capability state;
- источники с `sudo`, private API или нестабильным форматом не включаются как обязательная основа.

## Критерии исследования

Для каждого кандидата проверить:

- license, maintenance status и minimum macOS;
- Apple silicon и Intel, macOS 13+;
- требуемые permissions и возможность работы без root;
- attach, launch-under-profiler или import-only режим;
- machine-readable output и стабильность schema;
- overhead на idle и под нагрузкой;
- воспроизводимость результата на фиксированном fixture;
- риск утечки секретов и возможность redaction;
- корректное различение observed, configured, profiled и inferred.

## Порядок реализации после исследования

1. Определить единый `DeveloperWorkloadGraph` и evidence contract поверх текущих process/agent services.
2. Добавить короткую read-only сессию и timeline системной памяти без profiler.
3. Научиться связывать workspace с IDE, агентом, language server, build/watch и MCP-процессами.
4. Проверить один Python и один JS fixture через импорт profiler report.
5. Добавить read-only MCP/API для запросов агента к текущей сессии и отчётам.
6. Только после измерения overhead и privacy-аудита проектировать рекомендации и deep profiling UI.

## Критерий отличия от обычного Activity Monitor

Направление имеет смысл, если MacCleaner на воспроизводимом fixture способен ответить на четыре вопроса одновременно:

1. какой developer-workload вырос;
2. какой компонент внутри него дал основной вклад;
3. чем подтверждена связь;
4. какое обратимое действие снизило нагрузку и подтвердилось повторным измерением.

Если доступны только PID и RSS, функция остаётся улучшенным process monitor и не считается Developer Memory Intelligence.

## Связанные материалы

- [Управление приложениями и наблюдаемость AI-агентов](application-control-and-agent-observability-analysis.md)
- [[Architecture]]
- [[Features]]
- [[Opportunities]]
