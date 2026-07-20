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

MacCleaner is a native macOS utility for understanding what is happening on your Mac and acting on it from one place. It combines live system monitoring, storage analysis, safe cleanup, process inspection, AI workload visibility, and practical diagnostics.

It does not treat cleanup as a one-click promise. MacCleaner shows what it found, keeps potentially destructive choices visible, and uses bounded, cancellable scans so deeper analysis does not turn into uncontrolled full-disk work.

## Understand, Clean, and Maintain

### System overview
The Dashboard brings together CPU, memory, disks, network, GPU, battery, temperatures, and top processes. Separate process and window views make it easier to see which apps are using resources and which individual instances are active.

### Storage and cleanup
Storage tools find large files, junk, exact duplicates, similar photos, app leftovers, and reclaimable local iCloud copies. Cleanup Advisor ranks opportunities by size, risk, and recovery cost, while Complete Analysis combines the main storage checks into one workflow.

### AI workload
MacCleaner treats local AI tools as part of the system workload. It connects supported agents with their active processes, memory use, MCP servers, skills, profiles, components, and local indexes.

### Utilities and diagnostics

The remaining tools cover startup items, Desktop organization, fans and thermals, keyboard and speaker checks, APFS and SMART diagnostics, network checks, Pake Apps, and local model fit.

<p align="center">
  <img src="./docs/assets-github/product-overview-titlebar.svg" alt="MacCleaner product overview" width="100%" /><br />
  <img src="./docs/images/MacCleaner.gif" alt="MacCleaner interface and features" width="100%" />
</p>

## Local AI Workload

The Agents view answers two practical questions: which tools are active, and what local footprint belongs to them. Everything is inspected on the Mac and shown only when the related tool or data is available.

<p align="center">
  <img src="./docs/readme-media/agents-showcase.png" alt="MacCleaner agent workload overview" width="100%" />
</p>

## Install

1. Download the `.dmg` from the [latest release](https://github.com/Jas952/MacCleaner/releases/latest).
2. Open it and drag `MacCleaner.app` into `Applications`.
3. Launch MacCleaner.

> The current build is not notarized. If macOS blocks the first launch, right-click the app, choose **Open**, and confirm once.

MacCleaner requires macOS 13.0 or newer. Some locations may require Full Disk Access; fan and sensor coverage depends on the Mac. SMART, Pake Apps, and LLM Library use their corresponding optional local CLI tools.

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
