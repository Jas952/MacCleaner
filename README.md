<p align="center">
  <img src="./docs/readme-media/hero-v2.png" alt="MacCleaner — native macOS system, storage, and AI workload utility" width="100%" />
</p>

<h1 align="center">MacCleaner</h1>

<p align="center">
  Native control for a cleaner, quieter, and more understandable Mac.
</p>

<p align="center">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift_5-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="macOS 13 or newer" src="https://img.shields.io/badge/macOS_13+-111827?style=for-the-badge&logo=apple&logoColor=white" />
  <img alt="Native SwiftUI application" src="https://img.shields.io/badge/Native-SwiftUI-147EFB?style=for-the-badge&logo=xcode&logoColor=white" />
  <img alt="Codex helped with development" src="https://img.shields.io/badge/Helped_by-Codex-111827?style=for-the-badge&logo=openai&logoColor=white" />
  <img alt="Gemini helped with development" src="https://img.shields.io/badge/Helped_by-Gemini-7C5CFF?style=for-the-badge&logo=googlegemini&logoColor=white" />
</p>

<p align="center">
  <img alt="Local-first analysis" src="https://img.shields.io/badge/Local--first-Analysis-19A974?style=flat-square" />
  <img alt="Trash-only safe cleanup" src="https://img.shields.io/badge/Trash--only-Safe_Cleanup-2F81F7?style=flat-square" />
  <img alt="AI workload visibility" src="https://img.shields.io/badge/AI_Workload-Visibility-8B5CF6?style=flat-square" />
  <img alt="Bounded deep scans" src="https://img.shields.io/badge/Bounded-Deep_Scans-F59E0B?style=flat-square" />
  <img alt="Hardware diagnostics" src="https://img.shields.io/badge/Hardware-Diagnostics-EA4AAA?style=flat-square" />
</p>

MacCleaner began with a personal problem: a Mac used for development and local AI agents gradually becomes difficult to read. Processes multiply, caches grow, storage fragments across tools, and useful maintenance actions end up scattered around the system.

The result is a native utility built with care for anyone who wants one calm place to understand the machine, recover space safely, inspect agent workloads, and reach practical diagnostics without switching between unrelated apps.

MacCleaner is more than a cleaner. It combines system monitoring, bounded storage analysis, safe cleanup, process inspection, app uninstalling, desktop organization, AI workload visibility, and a set of focused maintenance tools.

## Everything in One Place

| Area | What it covers | How it works |
| --- | --- | --- |
| Dashboard | CPU, memory, disks, network, GPU, battery, temperature, and top processes | Reads native Mach, IOKit, IORegistry, CoreGraphics, network interface, and mounted-volume data with screen-aware refresh cadence. |
| Processes and Windows | App groups, individual PIDs, CPU, memory, disk activity, runtime, and visible windows | Combines process snapshots with executable identity and CoreGraphics window ownership. |
| Optimize | RAM guidance, user-space junk, DNS refresh, maintenance tasks, and startup items | Ranks reviewable actions, uses explicit confirmation, and keeps startup changes reversible. |
| Storage | Disk Map, Large Files, Junk, Cleanup Advisor, Uninstaller, and Complete Analysis | Walks selected roots with visible entry and time budgets; Efficient and Thorough modes can be cancelled. |
| Exact Duplicates | Byte-identical file groups with one retained copy | Narrows candidates by metadata and quick fingerprints, then proves matches with full SHA-256. |
| Similar Photos | Visually related photos for user review | Creates private 512 px ImageIO/Vision feature prints locally and rechecks selected files before cleanup. |
| Cloud Reclaim | Recoverable local space used by confirmed iCloud files | Evicts only the local copy after checking cloud state; the cloud copy is not deleted. |
| Desktop | Grid, list, columns, canvas, preview, rename, move, organize, and Trash | Works directly with the selected folder while preserving explicit user control over file actions. |
| Agents and Indexes | Local agents, processes, MCP servers, skills, components, profiles, and index stores | Correlates known tool locations and configuration with live resource usage on the Mac. |
| Tools and Diagnostics | Fans, thermals, keyboard, pointer, speakers, storage health, APFS, SMART, and network | Uses available macOS frameworks and optional local system utilities, with hardware-dependent fallbacks. |

All migrated user-facing cleanup flows share one safety policy: paths are normalized, MacCleaner data and sensitive locations are protected, and selected files move through macOS Trash. If Trash fails, the operation stops instead of silently switching to permanent deletion.

## Measured Results

The figures below come from Release builds tested on the same Mac with the same toolchain. The cadence and capacity comparison measures v1.0 against the optimized architecture introduced in v1.1; the current v1.2 test barrier was verified again for this README update.

| Result | Verified effect |
| --- | --- |
| **39/39 tests passing** | Current safety and policy suite passes for paths, Trash semantics, scan budgets, duplicates, similar photos, cloud reclaim, startup items, and process aggregation. |
| **94.2% fewer idle process snapshots** | Background process collection moved from every 105 seconds to every 1,800 seconds when no active screen needs it. |
| **3.5× fresher process data** | The active Processes screen refresh interval improved from 105 seconds to 30 seconds. |
| **up to 33.3× more scan capacity** | Thorough storage scans increased the entry budget from 30,000 to 1,000,000 while retaining deadlines and cancellation. |
| **6.67× more capacity in Efficient mode** | The low-load storage budget increased from 30,000 to 200,000 entries. |
| **91.7% fewer external battery scans** | Expensive `system_profiler` collection moved from every 30 minutes to every 6 hours while idle. |
| **50% fewer idle refreshes** | General idle monitoring changed from every 15 seconds to every 30 seconds. |
| **50% fewer idle sensor scans** | Temperature and fan sampling changed from every 60 seconds to every 120 seconds while idle. |
| **0 hard-delete fallbacks** | Migrated user-facing cleanup flows report a Trash error instead of permanently deleting the file. |

These are cadence, scan-capacity, safety-policy, and regression results rather than a synthetic “cleaner score.” The same comparison recorded a larger bundle and about 7.2% higher average launch RSS, so footprint remains an explicit optimization target. The complete methodology and trade-offs are recorded in the [measurement report](./docs/maccleaner-v1.0-vs-v1.1-summary.md).

<p align="center">
  <img src="./docs/assets-github/product-overview-titlebar.svg" alt="MacCleaner product overview" width="100%" /><br />
  <img src="./docs/images/MacCleaner.gif" alt="MacCleaner interface and features" width="100%" />
</p>

## Agent Workload, Made Visible

MacCleaner treats local AI tooling as part of the system workload. The Agents area identifies supported runtimes and shows their active processes, memory use, MCP bridges, skills, components, profiles, and local indexes in one view.

This makes the agent footprint concrete: which tools are active, what resources they use, which integrations are installed, and where their local working data lives. The analysis remains on the Mac and adapts to the tools and permissions actually available.

<p align="center">
  <img src="./docs/readme-media/agents-showcase.png" alt="MacCleaner agent workload overview" width="100%" />
</p>

## Additional Toolbox

| Tool | What it adds |
| --- | --- |
| Cleanup Advisor | Ranks reclaim opportunities by size, risk, and recovery cost. |
| Complete Analysis | Runs Advisor, Duplicates, Similar Photos, and Cloud Reclaim as one bounded workflow with a combined result. |
| App Uninstaller | Finds related user-space leftovers and presents them for review before Trash. |
| Startup Optimizer | Measures LaunchAgent impact and supports reversible disable and restore. |
| Desktop Manager | Adds visual organization, file preview, metadata, rename, move, and sorting workflows. |
| Pake Apps | Creates standalone web applications when the optional local `pake` tool is available. |
| LLM Library | Browses and evaluates local model fit through the optional `llmfit` tool. |
| Updates | Uses Sparkle with an HTTPS, EdDSA-signed appcast for manual and background update checks. |

## Install MacCleaner

<p align="center">
  <a href="https://github.com/Jas952/MacCleaner/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_DMG-2F81F7?style=for-the-badge&logo=apple&logoColor=white" alt="Download the latest MacCleaner DMG" />
  </a>
</p>

1. Open the [latest release](https://github.com/Jas952/MacCleaner/releases/latest).
2. Download the `.dmg` file from **Assets**.
3. Open it and drag `MacCleaner.app` into `Applications`.
4. Launch MacCleaner.

> If macOS blocks the first launch, right-click `MacCleaner.app`, choose **Open**, then confirm once.

## Contact

<p>
  <img src="./docs/assets-github/n1.gif" alt="Project author avatar" width="92" height="92" align="left" />
</p>
<pre hspace="12">
  <img src="./docs/assets-github/contacts/tg.jpg" alt="Telegram" height="14" /> Telegram ······ <a href="https://t.me/Jas953/">t.me/Jas953</a>
  <img src="./docs/assets-github/contacts/lnk.jpg" alt="LinkedIn" height="14" /> LinkedIn ······ <a href="https://www.linkedin.com/in/jas952/">linkedin.com/in/jas952</a>
  <img src="./docs/assets-github/contacts/x.jpg" alt="X" height="14" /> X        ······ <a href="https://x.com/not__jas">x.com/not__jas</a>
</pre>
<br clear="left" />
