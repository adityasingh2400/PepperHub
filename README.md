<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="168" alt="Pepper — peptide tracking for iOS" />
</p>

<h1 align="center">Pepper</h1>

<p align="center">
  <strong>Voice-first peptide stack tracking for iOS</strong><br />
  Research-oriented compound catalog, dosing math, timelines, and stack import from Notes or speech.
</p>

---

## Overview

**Pepper** (display name in the app; project target **Peptide**) helps people organize **what they run**, **how they dose**, and **how compounds behave over time**—with a bias toward fast input (voice, paste from Apple Notes) and clear pharmacokinetic visuals.

### Highlights

| Area | What ships |
|------|------------|
| **Stack** | Single “Stack” hub: import from **Notes** (paste / `PasteButton`) or **Voice**; review sheet with dose + frequency editors |
| **Blends** | **CJC-1295 + Ipamorelin** detected as **one vial** when the transcript signals a blend, `cjc/ipamorelin`-style shorthand, or typical **no DAC** combo language; STT fixes like **“Amarillo” → Ipamorelin** |
| **Catalog** | Offline **24-compound** starter set with aliases, conservative fuzzy matching for messy dictation, PK fields for timelines |
| **Timelines** | `PeptideTimelineView`: concentration-style curves, compact + expanded modes |
| **Voice** | Live transcription vocabulary hints; **Ask Pepper** handoff; long-press FAB for voice navigation |
| **Math** | `SyringeMath` for reconstitution / draw suggestions; `DosingFormula` mini-evaluator |
| **Backend** | Optional **Supabase** sync + migrations under `supabase/`; seed scripts in `scripts/` |

---

## Requirements

- **macOS** with **Xcode 16+** (Swift 6)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — regenerate the Xcode project from `project.yml`
- **iOS 17+** deployment target
- **Apple Developer** account (Personal Team is fine) for device builds

---

## Quick start

### 1. Clone and generate the project

```bash
git clone https://github.com/adityasingh2400/PepperHub.git
cd PepperHub   # or your local folder name
xcodegen generate
open Peptide.xcodeproj
```

### 2. Code signing (local, not committed)

The repo includes **`signing.local.xcconfig.example`**. Copy it and fill in **your** team ID and bundle ID:

```bash
cp signing.local.xcconfig.example signing.local.xcconfig
```

Edit `signing.local.xcconfig`:

```xcconfig
LOCAL_DEVELOPMENT_TEAM = YOUR10CHARID
LOCAL_BUNDLE_ID = com.yourname.pepper
```

`signing.local.xcconfig` is **gitignored** so team IDs and unique bundle IDs do not collide across contributors.

### 3. Run

Select an **iPhone simulator** or a **physical device**, then **⌘R**.

**Tests:** **⌘U** or:

```bash
xcodebuild -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

## Repo layout

| Path | Purpose |
|------|---------|
| `Sources/` | Swift app: `App`, `Models`, `Services`, `Views`, `Supporting` |
| `Resources/` | Assets (including **App Icon** in `Assets.xcassets`) |
| `Tests/` | `XCTest` targets (parser, dosing math, voice intent, etc.) |
| `data/` | `compound_metadata.yaml`, `veo_prompts.yaml` |
| `scripts/` | Bun/TS loaders for Supabase + Veo — see **[scripts/README.md](scripts/README.md)** |
| `supabase/migrations/` | SQL migrations |
| `project.yml` | XcodeGen definition |

---

## Configuration & secrets

- **Supabase (required for sign-in / sync):** copy `Sources/Supporting/APIKeys.swift.example` → `APIKeys.swift` and set **`supabaseURL`** (Project URL) and **`supabaseAnonKey`** (anon public key) from [Supabase Dashboard](https://supabase.com/dashboard) → *Project Settings* → *API*. Both must come from the **same** project; the URL must resolve in a browser (`https://<ref>.supabase.co`).
- **Anthropic / ElevenLabs:** same `APIKeys.swift` file — see the example. Do not commit real secrets.
- **RevenueCat** and other keys: follow your usual pattern; do not commit production secrets.

---

## Contributing

1. Branch from `main`, keep changes focused.
2. Run **tests** before pushing.
3. Regenerate with **`xcodegen generate`** when you change **`project.yml`** or add source files that XcodeGen should pick up.

---

## License / trademark

“Pepper” here refers to this app project. Peptide names and clinical context are for **education and personal tracking** only—not medical advice.

---

<p align="center">
  <sub>Icon: maroon / cream peptide-vial motif · in-repo asset shown above</sub>
</p>
