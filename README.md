# BPM Pulse

A gesture-aware BPM (Beats Per Minute) metronome and tempo tracker for HarmonyOS, built on **HarmonyOS Design System (HDS)** and the **HarmonyOS 26.0.0** SDK.

> Package name: `com.devon.bpmpulse` · Version: `1.0.0` · Target SDK: HarmonyOS `26.0.0 (API 26)`

## Highlights: HDS + HarmonyOS 26.0.0 APIs

This project is a reference for adopting the latest HarmonyOS design system and 26.0.0 APIs on ArkTS / ArkUI.

- **HDS Immersive Material** — Uses `uiMaterial.ImmersiveMaterial` (`@kit.ArkUI`) via `systemMaterial()` on the floating action button, the save dialog, and the search bar. The system takes over blur background, border, and shadow, so no hand-written blur is needed (THICK for buttons/dialogs, THIN for search field, per HDS guidance).
- **HDS Symbol Glyphs** — Search entry uses `SymbolGlyph($r('sys.symbol.magnifyingglass'))` from the HDS symbol font instead of image assets.
- **Smart Hold (智感握持)** — `motion.on('holdingHandChanged')` from `@kit.MultimodalAwarenessKit` detects left/right/both-hand grip and auto-flips the floating button side for one-handed tapping.
- **Haptics 26.0.0 API** — `vibrator.startVibration(...)` from `@kit.SensorServiceKit` with the new `usage` parameter (`'touch'` low-latency feedback, `'physicalFeedback'` for reset), plus `isSupportEffect('haptic.effect.hard')` preset effect and graceful fallback.
- **Canvas visibility recovery** — `onVisibleAreaChange([0.0, 1.0], ...)` (26.0.0) restarts the heartbeat-wave animation when the tab is scrolled back into view; `onReady()` is the official draw-start point after SDK upgrade.
- **Safe-area clipping** — `Scroll().clipContent(ContentClipMode.SAFE_AREA)` keeps content within the safe area on 26.0.0.
- **Spring edge effect** — `edgeEffect(EdgeEffect.Spring)` for natural overscroll feedback.

## Features

- Tap anywhere to the beat to measure BPM; long-press to reset.
- Attach song name and artist to each measurement.
- View, multi-select, delete, and share saved BPM records (persisted locally).
- Search by song, artist, or BPM, with clearable recent-search history.
- All data stored on-device; nothing is uploaded.

## Screens

| Tab / Page | Purpose |
| ---------- | ------- |
| BPM | Tap-to-measure tempo, live BPM, save with song info |
| Records | Saved BPM records, multi-select, delete, share |
| Search | Search songs/artists/BPM with recent-search history |

## Architecture

Standard HarmonyOS (ArkTS / ArkUI) structure, with HDS material and 26.0.0 APIs applied across the UI layer.

```
bpmpulse/
├── AppScope/                   # App-level config (app.json5, icons)
├── entry/                      # Main module
│   └── src/main/ets/
│       ├── entryability/       # EntryAbility (app entry)
│       ├── entrybackupability/ # Backup extension ability
│       ├── pages/              # BpmPage, RecordPage, SearchPage, Index
│       ├── models/             # SongRecord data model
│       └── database/           # DatabaseHelper, RecentSearchStore
├── build-profile.json5         # Build / signing / SDK config (target 26.0.0)
├── oh-package.json5            # Deps: hypium, hamock (testing)
└── hvigorfile.ts               # Build pipeline
```

- Language: ArkTS (ArkUI declarative UI) · Device: Phone
- Permissions: `ohos.permission.DETECT_GESTURE`, `ohos.permission.VIBRATE`
- Kits used: `@kit.ArkUI`, `@kit.MultimodalAwarenessKit`, `@kit.SensorServiceKit`, `@kit.BasicServicesKit`

## Requirements

- DevEco Studio compatible with HarmonyOS SDK `26.0.0 (API 26)`
- A HarmonyOS phone (API 26) device or emulator

## Build and Run

1. Open the project in DevEco Studio.
2. Install the HarmonyOS SDK `26.0.0 (API 26)`.
3. Select the `entry` module and a connected device or emulator.
4. Run the `debug` build, or build `release` with the configured signing profile.

## License

Licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.
