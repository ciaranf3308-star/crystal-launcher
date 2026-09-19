# Crystal Manager ↔ Crystal Launcher data contract

Version: 1 (POC)
Date: 2026-09-19
Status: DRAFT — implemented by the POC launcher; the Manager export side
(`config.json`, `launcher/profiles.json`) does not exist yet. The POC ships
with a `poc-config.json` fixture that mirrors this contract exactly.

## 1. Purpose

Defines the files the Crystal Launcher (Godot) reads from shared storage.
The launcher is a **presentation layer only**: it never scrapes, imports,
writes the index, or authors emulator configuration. The Manager owns all
data; the launcher consumes it.

## 2. Shared root layout

All paths below are relative to the shared data root, `crystal-nova-data/`:

```
crystal-nova-data/
├── config.json                  # NEW — written by Manager (see §3)
├── index.json                   # game index (existing, v1)
├── launcher/
│   └── profiles.json            # NEW — emulator recipes, written by Manager (see §7)
├── games/
│   └── <platform>/<gameId>/
│       ├── front.png            # BOX_FRONT
│       ├── spine.png            # BOX_SPINE (generated)
│       ├── back.png             # BOX_BACK
│       ├── media.png            # PHYSICAL_MEDIA (disc/cartridge)
│       ├── fullcover.png        # FULL_COVER (currently never written)
│       ├── logo.png             # CLEAR_LOGO (marquee/wheel)
│       ├── screenshot.png       # SCREENSHOT
│       └── manifest.json        # per-game rich metadata (existing)
└── cache/                       # Manager-internal, launcher MUST ignore
```

## 3. config.json (NEW)

Written by the Manager at every BUILD. Tells the launcher where everything lives.

```json
{
  "version": 1,
  "romRoot": "/storage/XXXX-XXXX/roms",
  "dataRoot": "/storage/XXXX-XXXX/crystal-nova-data",
  "indexPath": "/storage/XXXX-XXXX/crystal-nova-data/index.json",
  "updated": 1720000000
}
```

- `romRoot`: absolute path prefix for `romRelativePath` in index entries.
- All paths are absolute; the launcher must not guess roots.

## 4. index.json (existing)

```json
{
  "version": 1,
  "games": {
    "<platform>/<gameId>": {
      "title": "Final Fantasy X",
      "platform": "ps2",
      "gameId": "final-fantasy-x",
      "fileName": "Final Fantasy X (USA).iso",
      "romRelativePath": "ps2/Final Fantasy X (USA).iso",
      "fileSize": 1234567890,
      "lastModified": 1720000000000,
      "completeness": "COMPLETE_CASE_AND_MEDIA",
      "assets": ["back", "front", "logo", "media", "screenshot", "spine"],
      "real": 4,
      "generated": 2,
      "region": "USA",
      "provider": "esde-import"
    }
  }
}
```

- Key = `"<platform>/<gameId>"`; `gameId` = slugified ROM basename.
- `assets[]` = sorted slot-name stems (filename minus `.png`).
- `completeness` ∈ `NO_MATCH, METADATA_ONLY, FRONT_ONLY, PARTIAL_CASE, COMPLETE_CASE, COMPLETE_CASE_AND_MEDIA`.
- The launcher needs only `title`, `platform`, `gameId`, `assets`, `completeness`; it must ignore unknown fields.

## 5. Media slots (existing)

| Slot stem | File | Typical source |
|---|---|---|
| `front` | `front.png` | scraper / ES-DE `covers/` |
| `spine` | `spine.png` | generated |
| `back` | `back.png` | ES-DE `backcovers/` / generated |
| `media` | `media.png` | ES-DE `physicalmedia/` / generated |
| `fullcover` | `fullcover.png` | — (never written today) |
| `logo` | `logo.png` | scraper / ES-DE `wheel/`, `marquees/` |
| `screenshot` | `screenshot.png` | scraper / ES-DE `screenshots/` |

Slot → Godot role: `front` → case face decal; `back` → inspect back face;
`spine` → box spine; `media` → disc/cartridge sticker; `logo` → floating
logo layer; `screenshot` → display surfaces/backgrounds.
Future: `fanart`, `titlescreen`, `video`, `manual` (need importer extension;
launcher must tolerate their absence).

## 6. ROM resolution

Absolute ROM path = `<romRoot>/<romRelativePath>` (join with exactly one `/`).
Multi-disc games: the index entry's `romRelativePath` points at the
canonical bootable file (cue/m3u/gdi) — the launcher passes it unchanged
to the emulator recipe.

## 7. launcher/profiles.json (NEW)

Exported by the Manager from `LauncherProfileStore` (USER choices preserved
with `source: "USER"`). One entry per platform slug the launcher supports.

```json
{
  "version": 1,
  "profiles": {
    "ps2": {
      "type": "STANDALONE",
      "package": "xyz.aethersx2.android",
      "activity": "xyz.aethersx2.android.EmulationActivity",
      "action": "android.intent.action.MAIN",
      "handoff": "EXTRA",
      "extraKey": "bootPath",
      "source": "AUTO"
    },
    "gba": {
      "type": "RETROARCH",
      "package": "com.retroarch.aarch64",
      "activity": "com.retroarch.browser.retroactivity.RetroActivityFuture",
      "core": "mgba_libretro_android.so",
      "source": "USER"
    }
  }
}
```

Field reference (mirrors the Manager's `LauncherProfile`):

| Field | Meaning |
|---|---|
| `type` | `RETROARCH` / `STANDALONE` / `VIEW_INTENT` / `CUSTOM` |
| `package` / `activity` | intent component (`activity` may be relative, e.g. `.ui.main.MainActivity`) |
| `action` | intent action |
| `core` | RETROARCH: core `.so` filename; absolute path = `/data/data/<package>/cores/<core>` |
| `handoff` | STANDALONE: `EXTRA` (putExtra `extraKey` = ROM path) or `DATA` (`dataPrefix` + ROM path as intent data) |
| `extraKey` / `dataPrefix` | per `handoff` |
| `grantUriPermission` | add `FLAG_GRANT_READ_URI_PERMISSION` (Azahar-class handoffs) |
| `command` | CUSTOM: reserved, not interpreted by the POC |
| `source` | `USER` (never auto-overwritten by Manager) / `AUTO` |

The launcher substitutes the absolute ROM path for `{file.path}` itself and
fires the equivalent native Intent via its Android plugin — the Manager's
`am start` serialization is Pegasus-only and is NOT part of this contract.

## 8. Intent recipe mapping (informative)

| Profile type | Intent construction |
|---|---|
| RETROARCH | action MAIN, component pkg/activity, extras `ROM`=path, `LIBRETRO`=/data/data/pkg/cores/core, `CONFIGFILE`=/storage/emulated/0/Android/data/pkg/files/retroarch.cfg, flag `ACTIVITY_SINGLE_TOP` |
| STANDALONE + EXTRA | action, component, `putExtra(extraKey, path)` |
| STANDALONE + DATA | action VIEW (usually), component, `setData(Uri.parse(dataPrefix + path))` |
| VIEW_INTENT | action VIEW, component, `setData(content/file URI of ROM)`, optional grant flag |

## 9. Version tolerance (launcher requirements)

- `config.json`, `index.json`, `profiles.json` each carry `version`.
- The launcher must parse `version` first, ignore unknown fields and unknown
  asset slots, and never crash on a newer minor version.
- On major version mismatch the launcher shows the failure screen, never a
  half-loaded library.
- Missing optional files (`profiles.json` absent, slot PNG absent) degrade
  gracefully: game shows without that layer / launch shows "not configured".

## 10. What the launcher MUST NOT do

No scraping, no ES-DE importing, no index writes, no profile authoring, no
metafile generation. Configuration lives in the Manager. The launcher may
keep a small local cache (thumbnails, last-selection) in its own app-private
directory — never inside `crystal-nova-data/`.

## 11. Android transport: Manager ContentProvider (2026-09-19)

On Android the file layout above is NEVER accessed via raw /storage paths:
scoped storage blocks cross-app raw access and the Manager's SAF grant does
not transfer. Instead the Manager exposes its data tree through a
ContentProvider; the launcher reads everything through it. The Manager is
the sole owner of storage permission.

- Authority: `io.crystalnova.manager.crystaldata`
- URI form: `content://io.crystalnova.manager.crystaldata/<data-root-relative path>`
  e.g. `content://io.crystalnova.manager.crystaldata/config.json`,
  `.../index.json`, `.../launcher/profiles.json`,
  `.../games/ps2/slug/front.png`, `.../games/ps2/slug/manifest.json`.
- `rom/<romRelativePath>` maps to the ROM under the Manager's romRoot
  (for the future emulator handoff — hand the content:// URI to the target
  app with FLAG_GRANT_READ_URI_PERMISSION).
- Access is restricted to the launcher package (`io.crystalnova.launcher`,
  enforced via Binder calling-UID check in the provider).
- The launcher performs zero storage setup: install Manager → BUILD →
  install Launcher → open → library appears. No folder picker, no manual
  file management.
- Desktop/dev keeps raw file access (contract paths as-is).
