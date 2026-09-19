# Crystal Launcher — Detailed Implementation Plan

Date: 2026-09-19
Status: PLAN — no product code beyond the POC. Pegasus untouched.
Predecessors: `crystal-launcher-research/investigation-report.md` (verdict: viable),
`docs/contract.md` v1 (DRAFT), POC skeleton validated in Godot 4.4.1 (desktop).

Product rule: a bespoke handheld console frontend where the collection feels
physical, animated and alive — not a nicer emulation theme.

---

## 1. Ground truth: what exists today

**Done and validated**
- Investigation (Socket closed-source; Plain Launcher proves the whole pattern:
  JSON intent recipes + one thin Android plugin + pre-launch state persistence).
- Data contract v1 (`docs/contract.md`): `config.json` + `index.json` +
  `launcher/profiles.json` + `games/<platform>/<gameId>/*.png` + `manifest.json`.
- POC Godot project: data layer, background texture pipeline (LRU + thumbnails),
  triple-redundant controller input, pooled 3D carousel (case/disc/logo/background),
  launch bridge (GDScript + Kotlin source), failure screen, selection persistence.
  Desktop smoke test passes; failure paths exercised honestly.
- Manager backend to preserve: `index.json` schema, `games/` media tree,
  `LauncherProfiles.kt` recipe table, `LauncherProfileStore` (USER/AUTO),
  `LauncherAutoConfig`/`EmulatorDetector`, scraper, ES-DE importer, updater channel.

**Not done (the actual work ahead)**
- Manager does not yet write `config.json` or `launcher/profiles.json`.
- CrystalPlugin Kotlin source not yet built to AAR; no APK export pipeline.
- No authored 3D models (primitives stand in); no Nova hardware validation at all.
- ES-DE importer still skips titlescreens/fanart/3D-boxes/videos/manuals.

**Hard gate for the whole project:** on-Nova performance numbers. Everything
before it is cheap; everything after it depends on it.

---

## 2. Phase plan

### Phase 1 — Manager export bridge (unblocks all device work)
Goal: the launcher reads real Nova data instead of the fixture.

Work (Manager repo, additive only):
- New `LauncherExport` module (or extension in `ScraperManager`): at every BUILD,
  write `crystal-nova-data/config.json` (`version`, `romRoot`, `dataRoot`,
  `indexPath`, `updated`) and `crystal-nova-data/launcher/profiles.json`
  (per-platform emulator recipes serialized from `LauncherProfileStore`,
  preserving USER/AUTO source flags).
- Contract versioning: launcher ignores unknown fields/slots so the two ship
  independently.
- Ship through the existing `dev_build` channel with a distinct version label.

Difficulty: Low. Gate: after BUILD on the Nova, both files exist and validate
against `docs/contract.md`; POC desktop run loads them via `--crystal-config`.

### Phase 2 — Plugin AAR + APK export pipeline
Goal: an installable launcher that boots honestly on the Nova.

Status 2026-09-19: CI pipeline GREEN. `.github/workflows/build-apk.yml`
(pinned Godot 4.4.1 + export templates, Java 17, Android SDK 34 toolchain,
Gradle-built CrystalPlugin AAR merged into the export, CI-generated debug
keystore, headless `--export-release`) produces `crystal-launcher.apk`
(verified: real APK, plugin class in classes.dex, arm64 Godot runtime).
Local builds deprecated — CI is the only build path.

Work (launcher project, isolated):
- Build `android/plugins/CrystalPlugin/` to AAR (needs Android SDK — local or CI).
  Surface: `launchEmulator(profileJson, romPath)`, `getInstalledPackages()`,
  storage-permission helpers. Keep it ~15 methods like the reference.
- Godot Android export templates + `export_presets.cfg`
  (package `io.crystalnova.launcher`, landscape, GL Compatibility default),
  debug-signed beta APK.
- Boot path: missing data → failure screen with the exact reason (already built).
- SELF-UPDATE (standing user requirement, 2026-09-19): the launcher must
  update through the app, never via manual APK downloads. CI publishes the
  APK to a rolling release + manifest.json (versionCode authority); the
  Godot app checks on boot, downloads the APK, and fires the install
  intent through the plugin (REQUEST_INSTALL_PACKAGES + package installer
  session). Same trust model as the Manager's dev-latest channel.

Difficulty: Medium. Gate: APK installs on the Nova, boots to the failure screen
when data is absent, finds real data when present, and self-updates from CI.
No 3D needed yet.

### Phase 3 — HARDWARE VALIDATION GATE (go / no-go)
Goal: replace speculation with numbers. Do this before authoring a single model.

Measure on the Nova, with the real library:
- Cold-start latency (target: library visible fast; 3D dressing streams in).
- Sustained fps in the carousel (is 60 realistic? is 30 acceptable?).
- Texture memory with thumbnails vs full-res; LRU budget that fits.
- Controller feel: D-pad repeat, A/B, shoulders; focus never lost.
- Storage: can the Godot app read the SAF tree / raw paths post-grant?
- Renderer decision: GLES3 vs Vulkan — from measurement, not default.
- Launch + return per emulator: RetroArch, NetherSX2, PPSSPP, Dolphin
  (quit → back on the same selected game; note per-emulator quirks).

Difficulty: Unknown (that's the point). Gate: written numbers + explicit
GO / NO-GO. NO-GO means stop — Pegasus remains the frontend, no shame in it.

### Phase 4 — POC completion: the on-device demo
Goal: the "Pegasus can't do this" moment, one system, real games.

Work:
- Authored PS2 case + disc models (`models/ps2/` per the existing spec README).
- Wire real slot textures (front/back/spine/media/logo/screenshot) into the
  carousel; screenshot-crossfade background; camera parallax; launch zoom.
- `launchEmulator` → real NetherSX2 boot; quit → resume on the same game.
- System: PS2 (richest physical-media story). Explicitly out: everything else.

Difficulty: Medium. Gate: on the Nova — press right, case/disc/logo/background
transition with real depth; press A, emulator opens the right game; quit,
back on the same game. This demo is the project's emotional proof.

### Phase 5 — Product core (the real project)
Goal: a daily-usable launcher across the library.

Work:
- Multi-system browser (system rows → per-system carousel).
- Texture pipeline tuned from Phase 3 numbers (thumbnail sizes, decode pool,
  LRU budget, idle frame-rate reduction).
- Return-path hardening per emulator (quirk table; on-device intent editor
  precedent exists in the reference).
- Per-system selection persistence; startup resume.
- Accessibility: no touch required for any normal flow.

Difficulty: High. Gate: full library browsable at target fps; launch/return
reliable on every configured emulator; survives process death.

### Phase 6 — Media depth (the 3D vision)
Goal: exploit the media library Pegasus can't.

Work (Manager, additive):
- ES-DE importer extension: `titlescreens/`, fanart, 3D-box, video, manual
  directories → new slots/paths (extends the existing `SLOT_DIRS` pattern;
  current six slots untouched).
- Launcher: platform model library — GBA/GB/GBC/N64 cartridges, PS1 jewel
  case + disc, GameCube case + mini-disc… one model set per platform,
  textures per game. No bespoke scene per ROM, ever.
- Inspect view: rotate case → back cover, screenshots, manual.
- Launcher APK delivery via the Manager updater (new artifact, version
  contract between the two).

Difficulty: Medium-High (model authoring is the long pole). Gate: fanart
environments + inspect mode working on at least 3 platforms on-device.

### Phase 7 — Beta coexistence, then the Pegasus decision
Goal: safe migration, no flag day.

- Both frontends read the same `crystal-nova-data/`; launcher ships as a beta
  channel in the Manager; user picks the default frontend.
- Pegasus stays installed and working throughout.
- Retirement of Pegasus (metafile pipeline, QML theme, `am` serialization)
  is a separate, explicit decision — only after the launcher proves itself
  across the full library on the Nova.

---

## 3. Preserve / discard (when the time comes)

Preserve: `index.json` + `games/` tree (the crown jewels), launcher recipe
table + profile store + auto-config/detection, scraper, ES-DE importer,
Manager as the maintenance/update utility.

Discard (only at Phase 7, explicit decision): `MetafileGenerator`,
`PegasusLibrary.inject()`, SAF metafile writes, `game_dirs.txt` merge,
`PegasusIntents` restart dance, `am` serialization, the QML theme.

## 4. Risks

- Nova performance — the only true unknown; Phase 3 exists to answer it.
- Storage permissions from a Godot app on the Nova's Android version.
- Per-emulator launch quirks (AetherSX2 double-launch precedent) — recipe
  escape hatches + on-device editor.
- Scope creep into a second Manager — the launcher stays a presentation
  layer: no scraping, no importing, no config authoring. Ever.
- Beta confusion (two frontends) — messaging, not technology.

## 5. Non-goals

No per-ROM bespoke scenes. No new emulator-config database (recipes are
reused verbatim). No touch-required flows. No Pegasus breakage before
Phase 7. No "2D cover grid with fades" — if Godot only gives us that,
there is no reason to migrate.

## 6. Recommended execution

Phase 1 + 2 now (cheap, additive, isolated) → Phase 3 gate → Phase 4 demo →
decision point → Phases 5–7. Do not start Phase 5 before the Phase 3 numbers
and the Phase 4 demo both land on the Nova.
