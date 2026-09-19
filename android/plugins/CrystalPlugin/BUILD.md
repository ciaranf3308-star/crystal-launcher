# CrystalPlugin — AAR build + APK export pipeline

> **CI IS THE ONLY SUPPORTED BUILD.** The local build path below is deprecated
> and kept for reference only. The user's PC must never be a build
> prerequisite — no Godot, Android SDK, Android Studio, or Gradle installs
> are expected on any developer machine.

## The build (GitHub Actions)

Workflow: `.github/workflows/build-apk.yml`
Repo: https://github.com/ciaranf3308-star/crystal-launcher (private)

Triggers: `workflow_dispatch` or push to `main`.

Pinned toolchain (see the workflow for exact versions):

| Tool | Pinned version |
|---|---|
| Java | 17 (Temurin) |
| Android cmdline-tools | 11076708 |
| SDK packages | platform-tools, platforms;android-34, build-tools;34.0.0 |
| Gradle | 8.10.2 |
| AGP / Kotlin | 8.5.2 / 1.9.24 (in `settings.gradle`) |
| Godot editor | 4.4.1-stable headless (`Godot_v4.4.1-stable_linux.x86_64`) |
| Export templates | 4.4.1-stable |
| godot-lib (plugin compileOnly) | `org.godotengine:godot:4.4.1.stable` (Maven Central, verified published) |

Pipeline steps:

1. Build the plugin: `gradle assembleRelease` in `android/plugins/CrystalPlugin`
   → `build/outputs/aar/CrystalPlugin-release.aar`.
2. Copy it to `android/plugins/CrystalPlugin/CrystalPlugin.aar` — the
   `CrystalPlugin.gdap` (`binary_type="local"`) expects exactly that filename;
   Godot 4.x picks the plugin up automatically at export time. No `.cfg`
   file is needed; the `.gdap` is the descriptor.
3. Download the pinned Godot headless editor + export templates; install
   templates to `~/.local/share/godot/export_templates/4.4.1.stable/`.
4. `export_presets.cfg` (committed at repo root) defines the Android preset:
   package `io.crystalnova.launcher`, versionCode 1 / `0.1.0-beta1`,
   arm64-v8a only, landscape (from `project.godot`), GL Compatibility,
   signed with a CI-generated debug key (`/home/runner/debug.keystore`,
   android/androiddebugkey — beta signing only, never a store release).
5. Headless export:
   `godot --headless --path . --export-release "Android" build/crystal-launcher.apk`
6. The APK is uploaded as the `crystal-launcher-apk` workflow artifact
   (30-day retention). Download it from the Actions run → install on Nova.

Development loop: **commit → GitHub Actions → downloadable APK → install/test on Nova.**

### What the plugin exposes (unchanged surface)

- `launchEmulator(payloadJson)` — builds a native Intent from a
  `profiles.json` recipe + ROM path, `startActivity()`. Failures emit the
  `launch_failed` signal with the exact reason.
- `getInstalledPackages()` — JSON array of visible installed packages.

The dependency `org.godotengine:godot:4.4.1.stable` is `compileOnly` — it is
provided by the Godot Android export at runtime.

## Deprecated: local build (reference only)

The steps below describe what CI does, for debugging CI failures. Do not
build locally as part of the normal loop.

### 1. Build the CrystalPlugin AAR (local)

Prerequisites: JDK 17, Android SDK, Gradle ≥ 8.7, network → Maven Central.

```sh
export ANDROID_HOME=$HOME/Android/Sdk
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

cd android/plugins/CrystalPlugin
gradle wrapper --gradle-version 8.10.2   # one-time
./gradlew assembleRelease
cp build/outputs/aar/CrystalPlugin-release.aar CrystalPlugin.aar
```

`compileSdk 34` / `minSdk 24` come from `build.gradle`; the packages above
are exactly what that needs.

### 2. Export the APK (local)

Needs the Godot 4.4.1-stable editor + 4.4.1-stable export templates from
https://github.com/godotengine/godot/releases/tag/4.4.1-stable
(templates → `~/.local/share/godot/export_templates/4.4.1.stable/`), a
keystore at the path in `export_presets.cfg`, then the headless export
from the CI section step 5.

## Boot-path honesty (already in the POC — do not regress)

`scenes/game_carousel.gd::_ready()`:

1. `CrystalData.load_all()` fails → failure screen with the exact load error.
2. No games for the system → failure screen ("No games indexed…").
3. Launch failure (plugin missing on desktop, bad profile, missing ROM,
   native exception) → failure screen with the exact reason via the
   `launch_failed` signal.

There is no stubbed-success path. `failure_screen.gd` shows the message
verbatim; fatal errors say "Close and restart the app.", recoverable ones
allow B / Esc to go back.

## Still missing for a Nova-installable APK (product, not build)

- The Nova itself: install APK, grant storage access, point it at real
  `crystal-nova-data/` (needs Phase 1's `config.json` / `profiles.json`
  export from the Manager — currently the POC only reads its fixture).
