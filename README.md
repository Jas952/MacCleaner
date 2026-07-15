<p align="center">
  <img src="./docs/readme-media/hero-v2.png" alt="MacCleaner — native macOS system, storage, and AI workload utility" width="100%" />
</p>

<h1 align="center">MacCleaner</h1>

<p align="center">
  <img alt="macOS 13 or newer" src="https://img.shields.io/badge/macOS_13+-111827?style=for-the-badge&logo=apple&logoColor=white" />
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift_5-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="Native SwiftUI application" src="https://img.shields.io/badge/Native-SwiftUI-147EFB?style=for-the-badge&logo=xcode&logoColor=white" />
  <img alt="Local-first analysis" src="https://img.shields.io/badge/Local--first-19A974?style=for-the-badge" />
</p>

<p align="center">
  <a href="https://github.com/Jas952/MacCleaner/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_DMG-2F81F7?style=for-the-badge&logo=apple&logoColor=white" alt="Download the latest MacCleaner DMG" />
  </a>
</p>

## What It Does

| Need | MacCleaner |
| --- | --- |
| Understand the system | CPU, memory, disks, network, GPU, battery, thermals, processes, and windows |
| Recover storage | Large files, junk, exact duplicates, similar photos, app leftovers, and local iCloud copies |
| See AI workload | Agent processes, memory use, MCP servers, skills, profiles, components, and local indexes |
| Maintain the Mac | Startup items, Desktop tools, fans, keyboard, speakers, APFS, SMART, and network diagnostics |

## Verified Facts

| Metric | Result | Why it matters |
| --- | ---: | --- |
| Permanent-delete fallback | **0** | If Trash fails, cleanup stops |
| Scan modes | **2** | Efficient for speed; Thorough for wider coverage |
| Exact-duplicate verification | **3 stages** | Metadata → 128 KB sample → full SHA-256 |
| Safety and policy tests | **39 passing** | Current XCTest suite passed on July 14, 2026 |
| Automatic update checks | **Every 6 hours** | HTTPS appcast with EdDSA verification |
| Performance benchmark | **Pending** | Percentages require the same corpus and Mac |

## Efficient vs Thorough

| Limit | Efficient | Thorough |
| --- | ---: | ---: |
| Duplicate minimum file size | 1 MB | 128 KB |
| Duplicate filesystem entries | 200,000 | 1,000,000 |
| Duplicate verification I/O | 40 GB | 500 GB |
| Similar photos | 500 | 2,000 |
| Photo comparisons | 75,000 | 1,000,000 |
| Photo time budget | 60 seconds | 5 minutes |

Both modes are bounded and cancellable. Thorough expands coverage; it is not an unlimited forensic scan.

<p align="center">
  <img src="./docs/assets-github/product-overview-titlebar.svg" alt="MacCleaner product overview" width="100%" /><br />
  <img src="./docs/images/MacCleaner.gif" alt="MacCleaner interface and features" width="100%" />
</p>

## Local AI Workload

<p align="center">
  <img src="./docs/readme-media/agents-showcase.png" alt="MacCleaner agent workload overview" width="100%" />
</p>

## Safety by Default

| Action | MacCleaner does | MacCleaner does not do |
| --- | --- | --- |
| File cleanup | Moves selected files through macOS Trash | Silently fall back to permanent deletion |
| Memory | Shows pressure and recommendations | Automatically kill apps or run privileged `purge` |
| Cloud reclaim | Evicts a confirmed local iCloud copy | Delete the cloud copy |
| Startup items | Supports reversible disable and restore | Modify protected Apple or MacCleaner items |
| Similar photos | Keeps the final choice with the user | Preselect files after the first scan |

## Install

1. Download the `.dmg` from the [latest release](https://github.com/Jas952/MacCleaner/releases/latest).
2. Open it and drag `MacCleaner.app` into `Applications`.
3. Launch MacCleaner.

> The current build is not notarized. If macOS blocks the first launch, right-click the app, choose **Open**, and confirm once.

| Requirement or limit | Current status |
| --- | --- |
| macOS | 13.0 or newer |
| File access | Some locations may require Full Disk Access |
| Fans and sensors | Coverage depends on Mac hardware |
| Optional tools | SMART, Pake Apps, and LLM Library require their corresponding local CLI |

<p align="center">
  <img alt="Codex helped with development" src="https://img.shields.io/badge/Helped_by-Codex-111827?style=flat-square&logo=openai&logoColor=white" />
  <img alt="Gemini helped with development" src="https://img.shields.io/badge/Helped_by-Gemini-7C5CFF?style=flat-square&logo=googlegemini&logoColor=white" />
</p>

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
