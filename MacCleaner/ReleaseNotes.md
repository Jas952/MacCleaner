# MacCleaner 1.0.8

## What's new

Menu bar graphs:

- Added a new **Graphs** section to the menu bar popover with **Process History** and **Thermal Surface** views.
- Process History tracks CPU, memory, and relative energy activity for active applications over the last 30 minutes or four hours. It includes linear and logarithmic scales, minor-process filtering, per-process colors, hover details, and honest indications for gaps in collected data.
- Thermal Surface maps available Mac temperature sensors onto an interactive 3D chassis view. You can rotate and zoom the surface, separate the heat and component layers, inspect internal zones, and view temperature severity, fan airflow, charging-port activity, and connected-display information when macOS exposes it.

![Process History](https://raw.githubusercontent.com/Jas952/MacCleaner/v1.0.8/docs/readme-media/releases/v1.0.8/process-history.png)

![Thermal Surface](https://raw.githubusercontent.com/Jas952/MacCleaner/v1.0.8/docs/readme-media/releases/v1.0.8/thermal-surface.png)

Other changes:

- Reduced unnecessary menu bar refresh work, reused the existing system monitor, bounded the local four-hour history, and paused hidden thermal animation to keep background overhead low.
- Improved process-history continuity, startup behavior, switching responsiveness, sensor and fan decoding, and layout alignment in both light and dark appearances.

## Install

1. Download `MacCleaner.dmg` below.
2. Open the DMG and drag MacCleaner to Applications.
3. Open MacCleaner from Applications. If macOS blocks the first launch, allow it in **System Settings → Privacy & Security**.

This build uses ad-hoc signing and is not notarized, so macOS may show an unknown-developer warning on first launch. Privileged manual fan control requires a future Developer ID build; fan telemetry remains available.
