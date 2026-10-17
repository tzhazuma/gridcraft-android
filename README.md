# ArtCraft on Android (arm64-v8a)

Android ports of the [ArtCraft / Crafting Apps](https://github.com/storytold) suite — pure Rust +
egui/eframe desktop applications, cross-compiled to Android arm64-v8a with the NDK.

Upstream ships macOS, Windows, Linux, FreeBSD and WASM (`apps/<app>-web`) builds and **no mobile
code at all**. The ports here follow upstream's own precedent: add an **L6 app crate**
(`apps/<app>-android`) that reuses the desktop engine and egui UI unchanged, and supply only the
platform shell. eframe already supports Android through `winit` + `android-activity` + `wgpu`, so
no JNI layer has to be written by hand.

## Ports in this repository

| App | Upstream | Package | Status |
|---|---|---|---|
| **GridCraft** | [`storytold/gridcraft`](https://github.com/storytold/gridcraft) | `ai.storyteller.gridcraft` | builds; APK verified |
| **ArtCraft Launcher** | [`storytold/craft-launcher`](https://github.com/storytold/craft-launcher) | `ai.storyteller.artcraft-launcher` | in progress |

## Build

```bash
git clone --depth 1 https://github.com/storytold/gridcraft.git src/gridcraft

source scripts/env.sh && artcraft_check_env
scripts/build-so.sh  gridcraft
scripts/make-shell.sh "$PWD/src/gridcraft" gridcraft-android \
    ai.storyteller.gridcraft GridCraft 0.7.0 gridcraft
scripts/build-apk.sh gridcraft
```

→ `out/GridCraft-0.7.0-android-arm64.apk`

`env.sh` pins the four things that are otherwise guaranteed to bite: `cargo +stable` (the default
toolchain is nightly and has no `aarch64-linux-android` std), `JAVA_HOME=/opt/homebrew/opt/openjdk@21`
(the system JDK is 27 and AGP 9.1 rejects it), the SDK's `platform-tools` on `PATH`, and a build
lock (18 GB of RAM; concurrent rustc on an egui/wgpu tree OOMs the machine).

See **[STATUS.md](STATUS.md)** for the full reproducible procedure, the measured evidence
(sizes, SHA-256, `aapt2` badging, `zipalign -P 16`, `readelf` LOAD alignment) and the complete
pitfall list.

## Layout

```
scripts/                build + device tooling
templates/android-shell Gradle skeleton (AGP 9.1.0 / Gradle 9.3.1 / JDK 21 / minSdk 31)
icons/<app>/res/        per-app vector adaptive icons
ports/<app>-android/    the port source (source of truth)
src/<app>/              upstream shallow clones (not committed)
out/                    APKs
```

## Licence

The port crates are derived from upstream projects licensed `MIT OR Apache-2.0`; the same terms
apply. Upstream is not affiliated with these ports.
