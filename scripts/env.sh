#!/bin/bash
# Shared environment for every ArtCraft Android build. `source` this; do not execute it.
#
# Facts this encodes (each one was a real failure at some point):
#   * rustup IS installed, but the *default* toolchain is nightly and has no
#     aarch64-linux-android std. `stable` (cargo 1.99.0) has it. So: always `cargo +stable`.
#   * adb lives in the SDK's platform-tools and gh lives in /opt/homebrew/bin; neither is on the
#     default PATH of a non-interactive shell.
#   * The system `java` is JDK 27, which AGP 9.1 rejects. JDK 21 is at
#     /opt/homebrew/opt/openjdk@21 and must be JAVA_HOME.
#   * `python3` on this machine resolves to a broken venv interpreter that silently runs nothing,
#     so scripts must call /usr/bin/python3 explicitly.
#   * 18 GB of RAM with 5 agents building at once OOMs the box: builds are serialised through
#     scripts/build-lock.sh and cargo is capped with CARGO_BUILD_JOBS.

export ARTCRAFT_HOME="${ARTCRAFT_HOME:-$HOME/artcraft-android}"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
export PATH="$HOME/.cargo/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:/opt/homebrew/bin:$PATH"

# Keep a whole fleet of concurrent cargo builds from exhausting 18 GB.
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

# Absolute paths (never rely on PATH resolution inside generated sub-scripts).
export ADB="$ANDROID_HOME/platform-tools/adb"
export PYTHON=/usr/bin/python3
export ARTCRAFT_BUILD_LOCK="$ARTCRAFT_HOME/scripts/build-lock.sh"
export ARTCRAFT_BUILD_LOG_DIR="${ARTCRAFT_BUILD_LOG_DIR:-$ARTCRAFT_HOME/logs}"

# The one physical device this workspace targets. Wireless debugging ports drift, so :5555 (the
# classic adbd port) is the first thing to try.
export ARTCRAFT_DEVICE_IP="${ARTCRAFT_DEVICE_IP:-10.20.102.152}"
export ARTCRAFT_DEVICE="${ARTCRAFT_DEVICE:-$ARTCRAFT_DEVICE_IP:5555}"

# Toolchain sanity: fail loudly here rather than 40 lines into a cargo error.
artcraft_check_env() {
  local bad=0
  for p in "$ANDROID_NDK_HOME" "$JAVA_HOME/bin/java" "$ADB"; do
    [ -e "$p" ] || { echo "env: MISSING $p" >&2; bad=1; }
  done
  if ! cargo +stable --version >/dev/null 2>&1; then
    echo "env: 'cargo +stable' not usable (rustup missing or stable not installed)" >&2; bad=1
  fi
  if ! rustc +stable --print target-libdir --target aarch64-linux-android >/dev/null 2>&1 \
     || [ ! -d "$(rustc +stable --print target-libdir --target aarch64-linux-android 2>/dev/null)" ]; then
    echo "env: stable is missing the aarch64-linux-android std; run:" >&2
    echo "       rustup target add --toolchain stable aarch64-linux-android" >&2
    bad=1
  fi
  return $bad
}

# Android packages of every port in this workspace.
artcraft_app_id() {
  case "$1" in
    gridcraft)       echo "ai.storyteller.gridcraft" ;;
    craft-launcher)  echo "ai.storyteller.artcraft-launcher" ;;
    *)               echo "ai.storyteller.$1" ;;
  esac
}
