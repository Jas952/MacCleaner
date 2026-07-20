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

- **Live dashboard** — CPU, memory, disk, network, GPU, battery, temperatures and top processes.
- **Storage analysis** — large files, junk, duplicates, similar photos, app leftovers and local iCloud copies.
- **Cleanup advisor** — shows size, risk and recovery cost before removing anything.
- **Process inspection** — active apps, background agents and resource usage.
- **Diagnostics** — APFS, SMART, keyboard, speakers, fans, thermals and network checks.
- **Local AI workload** — agents, MCP servers, skills, profiles, local indexes and related processes.

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
