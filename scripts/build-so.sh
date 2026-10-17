#!/bin/bash
# Build one port's Rust cdylib for Android arm64-v8a.
#
#   build-so.sh <app>          e.g. build-so.sh gridcraft
#
# Reads   ports/<app>-android/          (source of truth, mirrored into the clone)
# Writes  src/<app>/apps/<app>-android/jniLibs/arm64-v8a/libmain.so
#
# Never pipe this through `tail`: the exit status must survive (that trap made a failed build
# look successful once).
set -uo pipefail

APP="${1:?usage: build-so.sh <app>   e.g. gridcraft}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"
artcraft_check_env || exit 2

CLONE="$ARTCRAFT_HOME/src/$APP"
PKG="$APP-android"
PORT="$ARTCRAFT_HOME/ports/$PKG"

[ -d "$CLONE" ] || { echo "FAIL: no clone at $CLONE"; exit 2; }
[ -d "$PORT" ]  || { echo "FAIL: no port source at $PORT"; exit 2; }

# The crate's package name need not match its directory: upstream's launcher is packaged
# `artcraft-launcher` but lives in `apps/artcraft-launcher-android` here. `-p` takes the package
# name, so read it from the port's own manifest rather than assuming.
CRATE="$(awk '/^\[package\]/{f=1;next} f&&/^\[/{exit} f&&/^name[[:space:]]*=/{gsub(/.*=[[:space:]]*"|".*/,"");print;exit}' "$PORT/Cargo.toml")"
[ -n "$CRATE" ] || { echo "FAIL: no [package] name in $PORT/Cargo.toml"; exit 2; }

# The port source is the source of truth: always re-mirror before building so an edit made in the
# clone can never silently win.
rsync -a --delete --exclude 'jniLibs' --exclude 'android' "$PORT/" "$CLONE/apps/$PKG/" || exit 2

# Profile: `--release` is right unless the app's release profile turns on debug info, in which
# case a dedicated `dist` profile exists for shipping (an app with `debug = "line-tables-only"`
# produced a 234 MB .so from --release and 46 MB from its dist profile).
PROFILE_FLAG="--release"
RELEASE_BLOCK="$(awk '/^\[profile\.release\]/{f=1;next} f&&/^\[/{f=0} f' "$CLONE/Cargo.toml")"
if printf '%s' "$RELEASE_BLOCK" | grep -qE '^[[:space:]]*debug[[:space:]]*=' \
   && grep -q '^\[profile\.dist\]' "$CLONE/Cargo.toml"; then
  PROFILE_FLAG="--profile dist"
fi

mkdir -p "$ARTCRAFT_BUILD_LOG_DIR"
LOG="$ARTCRAFT_BUILD_LOG_DIR/build-$APP.log"
echo "== $PKG   profile=$PROFILE_FLAG   jobs=$CARGO_BUILD_JOBS"
echo "== log: $LOG"

# The build script is generated with a QUOTED heredoc and placeholders, then sed'd. Never pass a
# command string through `bash -c "..."` with embedded quotes: the outer expansion mangles PATH
# and then not even `cc` resolves.
INNER="$(mktemp -t "artcraft-inner-$$")"
[ -n "$INNER" ] && [ -f "$INNER" ] || { echo "FAIL: could not create temp build script"; exit 2; }
cat > "$INNER" <<'INNER_EOF'
#!/bin/bash
set -uo pipefail
cd "__CLONE__"
export PATH="$HOME/.cargo/bin:$PATH"
export ANDROID_HOME="__ANDROID_HOME__"
export ANDROID_NDK_HOME="__NDK__"
export JAVA_HOME="__JAVA_HOME__"
export CARGO_BUILD_JOBS="__JOBS__"
# Strip the build machine's identity out of the shipped binary: rustc bakes absolute panic
# location paths into the object code, so without this every published APK leaks
# /Users/<name>/... to anyone running `strings libmain.so`.
export RUSTFLAGS="--remap-path-prefix=$HOME=/build --remap-path-prefix=__CLONE__=/src"
echo "[inner] cc: $(command -v cc || echo NOT_FOUND)"
exec cargo +stable ndk -t arm64-v8a -o "apps/__PKG__/jniLibs" build __PROFILE__ -p __CRATE__
INNER_EOF
sed -i '' \
  -e "s|__CLONE__|$CLONE|g" \
  -e "s|__PKG__|$PKG|g" \
  -e "s|__CRATE__|$CRATE|g" \
  -e "s|__PROFILE__|$PROFILE_FLAG|g" \
  -e "s|__ANDROID_HOME__|$ANDROID_HOME|g" \
  -e "s|__JAVA_HOME__|$JAVA_HOME|g" \
  -e "s|__JOBS__|$CARGO_BUILD_JOBS|g" \
  -e "s|__NDK__|$ANDROID_NDK_HOME|g" \
  "$INNER"
chmod +x "$INNER"

"$ARTCRAFT_BUILD_LOCK" "$INNER" > "$LOG" 2>&1
rc=$?
rm -f "$INNER"

echo "== cargo exit code: $rc"
if [ "$rc" -ne 0 ]; then
  echo "== errors =="
  grep -E '^error' -A8 "$LOG" | head -50
fi
SO="$CLONE/apps/$PKG/jniLibs/arm64-v8a/libmain.so"
if [ -f "$SO" ]; then echo "== artifact: $SO ($(stat -f%z "$SO") bytes)"; else echo "== (no libmain.so produced)"; fi
exit $rc
