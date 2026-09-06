# MacCleaner 1.0.9

## What's new

Fan control:

- Added a dedicated **Fan control** tab to the menu bar popover with live RPM, operating mode, target range, and temperature context for each detected fan.
- Supported Macs can return individual fans to macOS Auto, choose a manual RPM, temporarily disable a channel, or run both fans at maximum speed for ten seconds.
- Added a compact live temperature chart with fan start, stop, mode, and RPM-change events, including navigation back to earlier activations.
- Local fan control can be enabled after standard macOS administrator approval. The helper is tied to the exact app build and returns controlled fans to Auto when MacCleaner disconnects or quits.

Other changes:

- Improved fan-mode confirmation, helper installation diagnostics, RPM decoding, and recovery after sleep or interrupted control.
- Reduced unnecessary menu bar animation work and refined graph switching, hit areas, and active Thermal Surface controls.

## Install

1. Download `MacCleaner.dmg` below.
2. Open the DMG and drag MacCleaner to Applications.
3. Open MacCleaner from Applications. If macOS blocks the first launch, allow it in **System Settings → Privacy & Security**.

This build uses ad-hoc signing and is not notarized, so macOS may show an unknown-developer warning on first launch. Fan control requires a one-time administrator approval for each newly signed build; telemetry remains available without enabling control.
