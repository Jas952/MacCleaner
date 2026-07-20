# MacCleaner 1.0.4

- Redesigned Junk Files and Optimize cleanup reports as expandable lists: category → subcategory/folder → concrete paths, item counts, and sizes.
- Added automatic selection for safe-to-remove entries while keeping protected, sensitive, and rebuildable data out of bulk cleanup.
- Added developer-focused storage categories for Xcode, SwiftPM, npm, pnpm, Python, Docker, Ollama, Hugging Face, browser caches, logs, and related tool artifacts.
- Improved Optimize so the user can review exactly what will be cleaned, reuse the selected scan scope on subsequent analyses, and access Startup items without a separate sidebar destination.
- Added targeted administrator authorization retry for Large Files only after a normal Trash operation reports a permission failure.
- Strengthened Trash-only deletion, MacCleaner data protection, open-browser checks, and dirty Git project confirmation.
- Added a session-safe Drop Shelf: originals remain untouched, drag-out uses disposable exports, and Copy for paste supports files, images, and text in destinations such as Telegram.
- Expanded Agents with local footprint and process context, and added native system load notifications with CPU, temperature, and top contributing processes.
- Updated Clipboard History keyboard insertion, menu bar telemetry presentation, Settings controls, documentation, and validation coverage.
