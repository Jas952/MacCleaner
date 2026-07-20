<p align="center">
  <img
    src="./docs/readme-media/hero-v2.png"
    alt="MacCleaner — native macOS system, storage, and AI workload utility"
    width="100%"
  />
</p>

<h1 align="center">MacCleaner</h1>

<p align="center">
  Native macOS utility for monitoring, cleaning and maintaining your Mac from one place.
</p>

<p align="center">
  <img
    alt="macOS 13 or newer"
    src="https://img.shields.io/badge/macOS_13+-111827?style=flat-square&logo=apple&logoColor=white"
  />
  <img
    alt="Swift 5"
    src="https://img.shields.io/badge/Swift_5-F05138?style=flat-square&logo=swift&logoColor=white"
  />
  <img
    alt="Native SwiftUI application"
    src="https://img.shields.io/badge/Native-SwiftUI-147EFB?style=flat-square&logo=xcode&logoColor=white"
  />
  <img
    alt="Local-first analysis"
    src="https://img.shields.io/badge/Local--first-19A974?style=flat-square"
  />
</p>

<p align="center">
  <a href="https://github.com/Jas952/MacCleaner/releases/latest">
    <img
      src="https://img.shields.io/badge/Download-Latest_DMG-2F81F7?style=for-the-badge&logo=apple&logoColor=white"
      alt="Download the latest MacCleaner DMG"
      height="34"
    />
  </a>
  &nbsp;
  <img
    src="https://img.shields.io/badge/Helped_by-Codex-111827?style=for-the-badge&logo=openai&logoColor=white"
    alt="Codex helped with development"
    height="34"
  />
  &nbsp;
  <img
    src="https://img.shields.io/badge/Helped_by-Gemini-7C5CFF?style=for-the-badge&logo=googlegemini&logoColor=white"
    alt="Gemini helped with development"
    height="34"
  />
</p>

<br />

## Overview

MacCleaner helps you understand what is happening on your Mac and clean unnecessary data without hiding the details.

It combines live system monitoring, storage analysis, safe cleanup, process inspection, AI workload visibility, and practical diagnostics in one native macOS app.

<p align="center">
  <img
    src="./docs/assets-github/product-overview-titlebar.svg"
    alt="MacCleaner product overview"
    width="100%"
  />
  <br />
  <img
    src="./docs/images/MacCleaner.gif"
    alt="MacCleaner interface and features"
    width="100%"
  />
</p>

## Features

- **System overview** — understand the current state of your Mac without switching between several system utilities. See live CPU and memory load, disk usage, network activity, GPU, battery, temperatures, fans, and the most resource-heavy processes. Key metrics can also stay visible in the menu bar.

- **Cleanup and storage** — discover where disk space is going and review what can be reclaimed before removing anything. MacCleaner can surface caches, logs, large files, duplicates, similar photos, application leftovers, developer data, and local iCloud copies. Quick cleanup tools and deeper storage analysis are available in the same workspace.

- **Processes and startup** — inspect what is currently running and what starts automatically with macOS. Search grouped processes, explore related activity, compare resource usage, and quit regular applications directly from MacCleaner.

- **Desktop and everyday tools** — manage common tasks without opening a collection of separate utilities. Preview, rename, move, and organize files; temporarily park content in Drop Shelf; sample screen colors; maintain Homebrew; and test keyboard, pointer, speakers, storage, and network health.

- <a href="https://github.com/tw93/Pake"><img src="https://img.shields.io/badge/GitHub-tw93%2FPake-181717?style=for-the-badge&logo=github&logoColor=white" alt="View tw93/Pake on GitHub" height="28" /></a> — turn preset services or any website into a lightweight standalone macOS application, then open and manage generated apps from the same screen. This section provides a simpler way to keep frequently used web services separate from browser tabs and profiles.

- **Local AI workspace** — make local AI tools visible as part of the Mac's real workload. MacCleaner can detect supported agents, related processes, MCP servers, skills, helper runtimes, local components, and vector stores, then connect them with their CPU and memory footprint.

- <a href="https://github.com/AlexsJones/llmfit"><img src="https://img.shields.io/badge/GitHub-AlexsJones%2Fllmfit-181717?style=for-the-badge&logo=github&logoColor=white" alt="View AlexsJones/llmfit on GitHub" height="28" /></a> — explore local language models based on what the current Mac can realistically run. Compare compatible models, search by publisher or use case, and review memory requirements, model size, context length, capabilities, quantization, and estimated performance.

MacCleaner brings monitoring, cleanup, file management, diagnostics, and local AI visibility into one native macOS workspace. Each section starts with a clear overview and provides deeper tools when more detailed inspection is needed.

## Local AI Workload

MacCleaner treats local AI tools as part of the system workload.

The Agents view shows which tools are active, how many resources they use, and what local components belong to them.

<p align="center">
  <img
    src="./docs/readme-media/agents-showcase.png"
    alt="MacCleaner agent workload overview"
    width="100%"
  />
</p>

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/Jas952/MacCleaner/releases/latest).
2. Open it and drag `MacCleaner.app` into `Applications`.
3. Launch MacCleaner.

> [!NOTE]
> The current build is not notarized. If macOS blocks the first launch, right-click the app, choose **Open**, and confirm once.

## Requirements

- macOS 13.0 or newer
- Some scans may require Full Disk Access
- Fan, sensor and SMART data depend on the Mac model
- Some tools may require optional local CLI utilities

## Philosophy

MacCleaner is not a magic one-click cleaner.

It shows what it found, keeps potentially destructive actions visible, and uses bounded, cancellable scans so deeper analysis does not turn into uncontrolled full-disk work.

## Contact

<p>
  <img
    src="./docs/assets-github/n1.gif"
    alt="Project author avatar"
    width="92"
    height="92"
    align="left"
  />
</p>

<pre hspace="12">
  <img src="./docs/assets-github/contacts/tg.jpg" alt="Telegram" height="14" /> Telegram ······ <a href="https://t.me/Jas953/">t.me/Jas953</a>
  <img src="./docs/assets-github/contacts/lnk.jpg" alt="LinkedIn" height="14" /> LinkedIn ······ <a href="https://www.linkedin.com/in/jas952/">linkedin.com/in/jas952</a>
  <img src="./docs/assets-github/contacts/x.jpg" alt="X" height="14" /> X        ······ <a href="https://x.com/not__jas">x.com/not__jas</a>
</pre>

<br clear="left" />
