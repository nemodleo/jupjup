<p align="center">
  <img src="docs/images/icon.png" width="96" alt="Jupjup icon">
</p>

<h1 align="center">Jupjup <sub>줍줍</sub></h1>

<p align="center">
  <b>Pick up any text on your Mac screen — one shortcut, straight to your clipboard.</b><br>
  Tables stay tables. Any script, no setup. Quiet, ink-and-paper design.
</p>

<p align="center">
  <a href="#install"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F1D1A?logo=apple&logoColor=E4DDCF"></a>
  <img alt="Universal" src="https://img.shields.io/badge/Apple%20silicon%20%7C%20Intel-Universal-1F1D1A">
  <img alt="35 languages" src="https://img.shields.io/badge/UI-35%20languages-C4553A">
  <a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-1F1D1A"></a>
  <img alt="Status: beta" src="https://img.shields.io/badge/status-beta-C4553A">
</p>

<p align="center">
  <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Jupjup menu and a copied table">
</p>

## Why Jupjup?

There are plenty of screen-OCR tools. Jupjup does three things they don't:

- **Tables stay tables.** Select a table on screen and paste it into Numbers, Excel or Google Sheets with the cells intact. Jupjup puts both tab-separated text and an HTML table on the clipboard. 98% cell accuracy on our HTML-table benchmark (`tools/table_bench.swift`).
- **Reads any script without setup.** Korean, Japanese, Chinese, Cyrillic, Thai, Arabic, Vietnamese… Jupjup reads in your languages first and, if that fails, tries the other scripts automatically. 97–100% on 12 languages in our tests.
- **Shows you what's happening, where you're looking.** A vermilion bracket stays on the area you selected, sweeps while reading, and stamps a seal when done. The notification in the corner does the same.

Everything runs on your Mac. No account, no server, nothing leaves the machine unless you keep the optional, counts-only crash/usage reports on.

## Features

| | |
|---|---|
| **One shortcut** | ⇧⌘2 (change it in the menu) → drag to select → the text is on your clipboard |
| **Two modes** | *Fast* (Live Text) or *Accurate* (Vision, tables, multi-script). Switch in the menu, or press **1** / **2** while selecting |
| **Tables** | Detected automatically; copied as TSV + HTML |
| **Whole window** | Press **Space** while selecting to pick a window instead |
| **Same spot again** | Press the shortcut again while selecting to reuse the last area |
| **Fix it before you paste** | Hover the notification: join lines, edit, or **Undo** (restores your previous clipboard) |
| **35 interface languages** | Auto-follows macOS; right-to-left layout for Arabic and Hebrew |
| **Busy-Mac warning** | Tells you when a heavy CPU load will slow reading down |

<p align="center">
  <img src="docs/images/capture-hint.png" width="760" alt="Selection hint bar with mode keys">
</p>

## Install

Jupjup is in **beta** and not yet notarized by Apple, so macOS will warn on first open.

**Build from source** (recommended for now)

```bash
brew install xcodegen          # once
git clone https://github.com/nemodleo/jupjup.git
cd jupjup
./build.sh                     # builds a Universal app, installs to /Applications, opens it
```

Requires Xcode (tested with 26.3). The first build downloads two Swift packages and takes a few minutes.

**Releases** — signed and notarized downloads are on the [roadmap](#roadmap).

### First launch

1. Press **⇧⌘2**. macOS asks for **Screen Recording** permission (Jupjup needs to *see* the screen to read it).
2. Turn Jupjup on in *System Settings › Privacy & Security › Screen & System Audio Recording*.
3. **Reopen Jupjup.** macOS only applies this permission to freshly launched apps. The first-run window has a *Reopen* button for this.

> If ⇧⌘2 does nothing, another app (TextSniper uses the same default) may own it. Jupjup tells you and lets you pick a different combo.

## Keys while selecting

| Key | Does |
|---|---|
| drag | select an area |
| Space | switch to picking a whole window |
| 1 / 2 | Fast / Accurate mode for this capture (also saved as the default) |
| ⇧⌘2 (your shortcut) | reuse the last area |
| esc | cancel |

## How it works

- **Accurate mode** uses Apple's Vision text recognizer. Vision picks *one* script model from the first language you ask for, so Jupjup reads with your languages first, checks what came back with the system language detector, and re-reads with other script models (Japanese, Chinese, Cyrillic, Thai, Arabic…) only when needed. Word boxes from Vision feed the table detector, which looks for vertical gutters that run through every row.
- **Fast mode** uses Live Text (VisionKit). Faster, lighter, no word positions — so no tables.
- If one engine reads nothing, Jupjup tries the other before giving up.
- All of it is on-device, in `Sources/Recognizer.swift`.

## Privacy

Jupjup never saves, uploads or logs what it reads. Screenshots live in memory for the duration of one capture.

Full policy: [PRIVACY.md](PRIVACY.md).

Optional **error & usage reports** (on by default, one click to turn off in the menu or the first-run window) send only *counts and categories* — "a capture finished, 2–5 lines, under a second, table: no" — to [Sentry](https://sentry.io) (crashes) and [TelemetryDeck](https://telemetrydeck.com) (usage). Never text, never images, never coordinates. The exact list is in `Sources/Reporting.swift`. Builds without report keys send nothing at all.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel (Universal build). Intel Macs have no Neural Engine, so recognition is slower there.

## Roadmap

- [ ] Developer ID signing and notarization (no more Gatekeeper warning)
- [ ] Downloadable releases and in-app updates
- [ ] Native-speaker review of the 31 machine-translated interface languages
- [ ] Capture history
- [ ] Mac App Store

## Contributing

Issues and pull requests are welcome.

- **Translations**: each language is one file in `Resources/Strings/<code>.json`. Fix a string, open a PR — no code needed.
- **Table recognition**: add a case to `tools/table_bench.swift` and run it; the goal is cells-correct, not just text-correct.
- **Design**: the app follows a design canvas (ink `#1F1D1A`, hanji `#E4DDCF`, one vermilion seal `#C4553A`). Please keep new UI inside that palette.

## Acknowledgements

- Apple Vision and VisionKit for on-device recognition
- Fonts: [Noto Serif KR](https://fonts.google.com/noto/specimen/Noto+Serif+KR) and [Cormorant Garamond](https://fonts.google.com/specimen/Cormorant+Garamond), both under the SIL Open Font License
- [Sentry](https://github.com/getsentry/sentry-cocoa) and [TelemetryDeck](https://github.com/TelemetryDeck/SwiftSDK) SDKs

## License

Jupjup is free software under the [GNU GPL v3](LICENSE). You may use, study, share and improve it; if you distribute a modified version, it must stay under the same license.

*줍다 (jup·da), verb — to pick something up off the floor, one piece at a time.*
