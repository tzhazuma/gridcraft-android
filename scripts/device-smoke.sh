#!/bin/bash
# Real-device smoke test for one ArtCraft Android port.
#
#   device-smoke.sh <app-id> <activity> <tag> [shot-name] [apk-path]
#     device-smoke.sh ai.storyteller.gridcraft .MainActivity GridCraft gridcraft-real
#
# Installs the APK, launches it, greps logcat for crashes and pulls a screenshot into shots/.
# Exits non-zero when the app is not healthy.
#
# Hard-won device rules this encodes (vivo PA2573 / Android 16):
#   * Install via /data/local/tmp + `pm install`, NEVER /sdcard: SELinux stops system_server
#     reading a fuse path, so the install fails with no useful message.
#   * The device MUST be unlocked. While the lockscreen is up vivo silently discards the install
#     (`pm install` prints nothing and `lastUpdateTime` never moves). The unlock gesture is a
#     two-finger swipe, which `adb shell input swipe` cannot produce, so this script refuses to
#     pretend: it reports the lock and stops rather than looping.
#   * `adb install` can hang forever on a large APK over wireless ADB. Every adb call is bounded.
set -uo pipefail

APP_ID="${1:?app id}"; ACTIVITY="${2:?activity, e.g. .MainActivity}"
TAG="${3:?logcat/apk tag}"; SHOT="${4:-${TAG}-real}"; APK_ARG="${5:-}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "$HERE/env.sh"

# ---------------------------------------------------------------- device selection
resolve_device() {
  local d
  d="$("$ADB" devices | awk '/\tdevice$/{print $1}' | grep -v '^emulator-' | head -1)"
  [ -n "$d" ] && { echo "$d"; return; }
  # Nothing attached: try the classic adbd port, which has rescued this session twice.
  for port in 5555 5556 5037; do
    "$ADB" connect "$ARTCRAFT_DEVICE_IP:$port" >/dev/null 2>&1
    d="$("$ADB" devices | awk '/\tdevice$/{print $1}' | head -1)"
    [ -n "$d" ] && { echo "$d"; return; }
  done
  # Last resort: mDNS.
  local svc
  svc="$("$ADB" mdns services 2>/dev/null | awk '/_adb-tls-connect/{print $3; exit}')"
  if [ -n "$svc" ]; then
    "$ADB" connect "$svc" >/dev/null 2>&1
    d="$("$ADB" devices | awk '/\tdevice$/{print $1}' | head -1)"
    [ -n "$d" ] && { echo "$d"; return; }
  fi
}

SERIAL="$(resolve_device)"
if [ -z "$SERIAL" ]; then
  echo "FAIL: no online device"; "$ADB" devices -l; exit 2
fi
echo "== device: $SERIAL"

# ---------------------------------------------------------------- lock gate
# `dumpsys window` is the cheap check; `mWakefulness` distinguishes asleep from awake-but-locked.
LOCK="$(timeout 30 "$ADB" -s "$SERIAL" shell dumpsys window 2>/dev/null | grep -m1 'mDreamingLockscreen')"
WAKE="$(timeout 30 "$ADB" -s "$SERIAL" shell dumpsys power 2>/dev/null | grep -m1 'mWakefulness=')"
echo "== $LOCK   $WAKE"
if printf '%s' "$LOCK" | grep -q 'mDreamingLockscreen=true'; then
  echo "HUMAN ACTION REQUIRED: the device is locked."
  echo "  vivo silently drops package installs while the lockscreen is up, and its unlock"
  echo "  gesture (two-finger swipe up) cannot be produced by 'adb shell input swipe'."
  echo "  Please unlock the phone by hand and re-run this script."
  exit 5
fi

# ---------------------------------------------------------------- apk
if [ -n "$APK_ARG" ]; then APK="$APK_ARG"; else
  APK="$(ls -t "$ARTCRAFT_HOME"/out/*"$TAG"*.apk 2>/dev/null | head -1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || { echo "FAIL: no APK found matching '$TAG' in $ARTCRAFT_HOME/out"; exit 2; }
echo "== apk: $APK ($(stat -f%z "$APK") bytes)"

# ---------------------------------------------------------------- install
# Push to /data/local/tmp and install from there: /sdcard is a fuse mount that system_server
# cannot read, so `pm install /sdcard/...` fails on SELinux.
REMOTE="/data/local/tmp/$(basename "$APK")"
echo "== push -> $REMOTE"
timeout 300 "$ADB" -s "$SERIAL" push "$APK" "$REMOTE" >/tmp/artcraft-push.log 2>&1
prc=$?
if [ "$prc" -ne 0 ]; then echo "FAIL: push (exit $prc)"; tail -3 /tmp/artcraft-push.log; exit 3; fi

# `-t` allows test-only packages; `-r` replaces. `-d` would allow a downgrade.
echo "== pm install -r -t"
timeout 300 "$ADB" -s "$SERIAL" shell pm install -r -t "$REMOTE" >/tmp/artcraft-install.log 2>&1
irc=$?
tail -3 /tmp/artcraft-install.log
if [ "$irc" -eq 124 ]; then
  echo "== install TIMED OUT — verifying by package presence"
  if "$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null | grep -q "$APP_ID"; then
    echo "== package IS present, continuing"
  else
    echo "FAIL: install timed out and $APP_ID is not installed"; exit 3
  fi
elif [ "$irc" -ne 0 ]; then
  echo "FAIL: install (exit $irc)"; exit 3
fi
"$ADB" -s "$SERIAL" shell rm -f "$REMOTE" >/dev/null 2>&1

# vivo's "install from unknown source" prompt is answered once per installer; if the package
# still is not there, the install was discarded (almost always the lockscreen).
if ! "$ADB" -s "$SERIAL" shell pm list packages 2>/dev/null | grep -q "$APP_ID"; then
  echo "FAIL: $APP_ID is not installed after pm install."
  echo "  Most likely the lockscreen dropped it, or vivo is waiting for a human to tap"
  echo "  'always allow' on the unknown-source dialog."
  exit 4
fi

# ---------------------------------------------------------------- launch
echo "== launch $APP_ID/$ACTIVITY"
"$ADB" -s "$SERIAL" logcat -c >/dev/null 2>&1
timeout 60 "$ADB" -s "$SERIAL" shell am start -n "$APP_ID/$ACTIVITY" || { echo "FAIL: am start"; exit 6; }
sleep 15

LOG="$(timeout 60 "$ADB" -s "$SERIAL" logcat -d 2>/dev/null | grep -Ei "$TAG|panick|AndroidRuntime|FATAL|wgpu|vulkan|eframe" | tail -60)"
echo "== logcat"; echo "${LOG:-<no matching lines>}"

echo "== verdict"
RC=0
if echo "$LOG" | grep -Eqi "FATAL|AndroidRuntime.*Exception|panicked"; then echo "FAIL: crash detected"; RC=1
elif [ -z "$LOG" ]; then echo "WARN: no matching log lines"; RC=1
else echo "PASS: launched, no crash"; fi

# Is the activity actually the focused window? A process that starts and immediately dies, or one
# stuck behind a splash screen, still produces log lines, so check the real foreground state.
FOCUS="$(timeout 30 "$ADB" -s "$SERIAL" shell dumpsys window 2>/dev/null | grep -m1 'mCurrentFocus')"
echo "== $FOCUS"
if printf '%s' "$FOCUS" | grep -q "$APP_ID"; then echo "PASS: activity is focused"; else echo "WARN: activity is not the focused window"; RC=1; fi

mkdir -p "$ARTCRAFT_HOME/shots"
timeout 60 "$ADB" -s "$SERIAL" exec-out screencap -p > "$ARTCRAFT_HOME/shots/${SHOT}.png" 2>/dev/null
if [ -s "$ARTCRAFT_HOME/shots/${SHOT}.png" ]; then
  echo "== shot: shots/${SHOT}.png ($(stat -f%z "$ARTCRAFT_HOME/shots/${SHOT}.png") bytes)"
else echo "WARN: screenshot empty"; RC=1; fi
exit $RC
