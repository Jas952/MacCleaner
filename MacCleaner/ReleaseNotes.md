# MacCleaner 1.0.4

- Redesigned Junk Files as a hierarchical list: category → folder/subcategory → concrete paths and sizes.
- Small files inside large folders are grouped into one aggregate row with the item count and total size.
- Safe, rebuildable, and downloadable-again data is selected automatically for cleanup.
- Developer and AI data is separated by owner, including Xcode, SwiftPM, npm, pnpm, Python, Docker, Ollama, Hugging Face, and other tools.
- Protected categories are hidden by default and can be revealed for review; they are excluded from bulk cleanup.
- Large Files now offers a targeted administrator authorization retry only after a normal permission failure.
- Strengthened Trash-only deletion, MacCleaner data protection, open-browser checks, and dirty Git project confirmation.
- Updated the Storage interface, safety explanations, documentation, and validation scenarios.
