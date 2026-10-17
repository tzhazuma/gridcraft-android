#!/bin/bash
# Assemble the APK for one port and copy it into out/.
#
#   build-apk.sh <app> [version-name]
#
# Requires libmain.so to already exist (run build-so.sh first). Uses the Gradle wrapper inside
# the clone's android/ project, with JDK 21 and the already-downloaded gradle-9.3.1 distribution.
set -uo pipefail

APP="${1:?usage: build-apk.sh <app> [version-name]}"
VERSION_NAME="${2:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"

CLONE="$ARTCRAFT_HOME/src/$APP"
PKG="$APP-android"
ANDROID_DIR="$CLONE/apps/$PKG/android"
SO="$CLONE/apps/$PKG/jniLibs/arm64-v8a/libmain.so"

[ -d "$ANDROID_DIR" ] || { echo "FAIL: no Gradle shell at $ANDROID_DIR (run make-shell.sh)"; exit 2; }
[ -f "$SO" ] || { echo "FAIL: no libmain.so at $SO (run build-so.sh first)"; exit 2; }

# The shell's jniLibs.srcDirs points at ../../jniLibs, which is where build-so.sh puts the .so.
mkdir -p "$ARTCRAFT_BUILD_LOG_DIR"
LOG="$ARTCRAFT_BUILD_LOG_DIR/apk-$APP.log"
echo "== assembling $PKG (JDK: $JAVA_HOME)"
echo "== log: $LOG"

# Bound the Gradle run: a stale daemon or a wedged dependency resolution must not hang forever.
( cd "$ANDROID_DIR" && JAVA_HOME="$JAVA_HOME" ./gradlew --no-daemon assembleRelease ) > "$LOG" 2>&1
rc=$?
echo "== gradle exit code: $rc"
if [ "$rc" -ne 0 ]; then
  echo "== errors =="
  grep -E 'error|FAILURE|What went wrong' -A6 "$LOG" | head -40
  exit $rc
fi

APK_SRC="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
[ -f "$APK_SRC" ] || { echo "FAIL: gradle succeeded but no APK at $APK_SRC"; exit 3; }

# A human-readable, upload-ready name. The version name is read back out of the shell's
# build.gradle when the caller did not pass one.
if [ -z "$VERSION_NAME" ]; then
  VERSION_NAME="$(grep -oE "versionName = \"[^\"]+\"" "$ANDROID_DIR/app/build.gradle" | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
fi
LABEL="$(grep -oE 'android:label="[^"]+"' "$ANDROID_DIR/app/src/main/AndroidManifest.xml" | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
[ -n "$LABEL" ] || LABEL="$APP"
# A display label may contain spaces ("ArtCraft Launcher"); a file name should not.
STEM="$(printf '%s' "$LABEL" | tr -d ' ')"
OUT="$ARTCRAFT_HOME/out/${STEM}-${VERSION_NAME}-android-arm64.apk"
mkdir -p "$ARTCRAFT_HOME/out"
cp -f "$APK_SRC" "$OUT"

echo "== apk: $OUT"
ls -la "$OUT"
# 16 KB page alignment is mandatory on Android 15+; verify rather than assume (NDK r28+ is fine).
ZIPALIGN="$ANDROID_HOME/build-tools/36.0.0/zipalign"
if [ -x "$ZIPALIGN" ]; then
  if "$ZIPALIGN" -c -P 16 -v 4 "$OUT" > "$ARTCRAFT_BUILD_LOG_DIR/zipalign-$APP.log" 2>&1; then
    echo "== zipalign -P 16: OK (16 KB page aligned)"
  else
    echo "== zipalign -P 16: FAILED — see $ARTCRAFT_BUILD_LOG_DIR/zipalign-$APP.log"
  fi
fi
echo "$OUT"
