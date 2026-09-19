# CrystalPlugin — AAR build + APK export pipeline

Phase 2 of the Crystal Launcher plan. This machine (build host, 2026-09-19)
has **no Android SDK and no Godot binary** — Java 17.0.20 only. Nothing here
has been compiled yet. Follow the steps below on a machine with the SDK.

## 1. Build the CrystalPlugin AAR

### Prerequisites

| Tool | Required | Status on build host |
|---|---|---|
| JDK 17 | yes (AGP 8.x) | present: OpenJDK 17.0.20 |
| Android SDK | yes | **missing** |
| Gradle ≥ 8.7 | yes | **missing** (generate wrapper, step 4) |
| Network → Maven Central | yes | needed for `org.godotengine:godot:4.4.1.stable` (verified published) |

### SDK packages to install

```sh
# After installing the SDK command-line tools, set ANDROID_HOME (or ANDROID_SDK_ROOT):
export ANDROID_HOME=$HOME/Android/Sdk

sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

`compileSdk 34` / `minSdk 24` come from `build.gradle`; the packages above
are exactly what that needs.

### Build steps

```sh
cd android/plugins/CrystalPlugin

# One-time: generate the wrapper (needs network; Gradle 8.7+ for AGP 8.5.2)
gradle wrapper --gradle-version 8.10.2

# Build the release AAR
./gradlew assembleRelease
```

### Where the AAR goes

Gradle outputs `build/outputs/aar/CrystalPlugin-release.aar`. Copy it to:

```
android/plugins/CrystalPlugin/CrystalPlugin.aar
```

That filename is what `CrystalPlugin.gdap` already declares
(`binary_type="local"`, `binary="CrystalPlugin.aar"`) — Godot 4.x picks the
plugin up automatically at export time. No `.cfg` file is needed for
Godot 4.x; the `.gdap` is the descriptor.

### What the plugin exposes (unchanged surface)

- `launchEmulator(payloadJson)` — builds a native Intent from a
  `profiles.json` recipe + ROM path, `startActivity()`. Failures emit the
  `launch_failed` signal with the exact reason.
- `getInstalledPackages()` — JSON array of visible installed packages.

The dependency `org.godotengine:godot:4.4.1.stable` is `compileOnly` — it is
provided by the Godot Android export at runtime. Version confirmed published
on Maven Central (2026-09-19).

## 2. Export the APK (Godot)

### Required versions — pin these

- **Godot editor: 4.4.1.stable** (matches `project.godot` `config/features`
  `"4.4"` and the plugin's godot-lib version). The POC was validated on 4.4.x.
  - Linux: `Godot_v4.4.1-stable_linux.x86_64`
  - From: https://github.com/godotengine/godot/releases/tag/4.4.1-stable
- **Android export templates: 4.4.1.stable**
  - File: `Godot_v4.4.1-stable_export_templates.tpz` (same release page)
  - Install to: `~/.local/share/godot/export_templates/4.4.1.stable/`
  - Neither the editor nor the templates are installed on the build host.

### export_presets.cfg

Not committed yet — generate it once in the editor (Project → Export →
Add… → Android), then commit it. Required settings:

- Preset name: `Android`
- Package → Unique Name: `io.crystalnova.launcher`
- Package → Name: `Crystal Launcher`
- Architectures: **ARM 64-bit only** (`arm64-v8a`; Nova is ARM64 — smaller APK)
- Orientation: **Landscape** (matches `display/window/handheld/orientation`)
- Renderer: GL Compatibility (comes from `project.godot`; do not override)
- Signing: debug keystore is fine for the beta (Godot generates one if none
  is configured). A dedicated release keystore comes later, before any
  user-facing release.

Export from the editor (or headless once templates exist):

```sh
godot --headless --export-release Android crystal-launcher-beta.apk
```

## 3. Boot-path honesty (already in the POC — do not regress)

`scenes/game_carousel.gd::_ready()`:

1. `CrystalData.load_all()` fails → failure screen with the exact load error.
2. No games for the system → failure screen ("No games indexed…").
3. Launch failure (plugin missing on desktop, bad profile, missing ROM,
   native exception) → failure screen with the exact reason via the
   `launch_failed` signal.

There is no stubbed-success path. `failure_screen.gd` shows the message
verbatim; fatal errors say "Close and restart the app.", recoverable ones
allow B / Esc to go back.

## 4. Still missing for a Nova-installable APK

1. Android SDK on a build machine (packages listed in §1).
2. Gradle ≥ 8.7 (or generate the wrapper once).
3. The compiled `CrystalPlugin.aar` in `android/plugins/CrystalPlugin/`.
4. Godot 4.4.1.stable editor + 4.4.1.stable Android export templates.
5. A committed `export_presets.cfg` (generate once in the editor per §2).
6. The Nova itself: install APK, grant storage access, point it at real
   `crystal-nova-data/` (needs Phase 1's `config.json` / `profiles.json`
   export from the Manager — currently the POC only reads its fixture).
