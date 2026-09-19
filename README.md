# Crystal Launcher — Godot POC

Isolated experimental frontend for Crystal Nova. **Does not touch the Manager
repo or Pegasus.** Read `docs/contract.md` first — it is the data contract
everything here codes to.

## What this POC proves (one system, real games)

1. Load the Manager's real `index.json` + real per-game media → `autoload/crystal_data.gd`
2. Controller navigation (D-pad + A/B, no touch, no hardcoded device ids) → `autoload/input_setup.gd`
3. Animated 3D selection — case + disc + floating logo + crossfading screenshot
   background, camera parallax, launch zoom — the "Pegasus can't do this" moment → `scenes/game_carousel.gd`
4. Launch a real installed emulator via the native bridge → `autoload/crystal_plugin.gd`
   + `android/plugins/CrystalPlugin/`
5. Return to the same selected game (selection persisted pre-launch, restored on start)

## Layout

```
docs/contract.md            Manager <-> Launcher data contract (read first)
project.godot               Godot 4.4, GL Compatibility, 1280x720 landscape
autoload/
  crystal_data.gd           index.json / media / manifest / profiles reader
  texture_cache.gd          background decode + LRU + thumbnails (the anti-jank layer)
  input_setup.gd            triple-redundant input map (keyboard + any-joypad)
  navigator.gd              minimal screen stack
  crystal_plugin.gd         GDScript side of the Android bridge
scenes/
  game_carousel.tscn/.gd    the POC: 3D physical-media browser
  failure_screen.tscn/.gd   honest failure surface
models/ps2/README.md        spec for the authored PS2 case+disc set (pending)
launcher_configs/intents.json  reference intent recipes (informative)
android/plugins/CrystalPlugin/ Kotlin plugin: launchEmulator, getInstalledPackages (AAR build pending — see android/plugins/CrystalPlugin/BUILD.md for exact steps)
poc-config.json             local fixture mirroring contract §3 (dev only)
```

## Status

- [x] Contract written
- [x] Data layer (config/index/media/manifest/profiles)
- [x] Background texture pipeline
- [x] Controller-first input map
- [x] 3D carousel with pooled slots, selection animation, logo + background layers
- [x] Launch bridge (GDScript + Kotlin), failure surface, selection persistence
- [ ] Authored PS2 case/disc models (primitives stand in)
- [ ] CrystalPlugin AAR build (needs Android SDK)
- [ ] Android APK export (needs Godot export templates)
- [ ] **Hardware validation on the Nova** — fps, startup latency, texture memory,
      controller feel, SD-card permission behavior, return-from-emulator per app

## Running (desktop smoke test)

Godot 4.4: open the project, press Play. It reads `res://poc-config.json`
(or `--crystal-config=<path>`). Without the Android plugin, launching shows
the failure screen with the exact reason — that path is exercised, not hidden.

## Deliberately out of the POC

Multi-system browser, inspect/manual views, per-game overrides, theme parity,
update channel, ES-DE importer extensions (fanart/titlescreens), Manager-side
`config.json` / `profiles.json` export.
