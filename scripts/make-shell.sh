#!/bin/bash
# Instantiate the Gradle shell for one app inside its upstream clone.
#
#   make-shell.sh <clone-dir> <pkg> <app-id> <label> <version-name> [icon-name]
#
#   make-shell.sh ~/artcraft-android/src/gridcraft gridcraft-android \
#                 ai.storyteller.gridcraft GridCraft 0.7.0 gridcraft
#
# Writes <clone-dir>/apps/<pkg>/android/ (Gradle project) and is idempotent: re-running
# re-mirrors the template, which is the source of truth, over whatever is there.
#
# The Gradle wrapper is taken from the template, so no network fetch of the distribution is
# needed: gradle-9.3.1 is already in ~/.gradle/wrapper/dists.
#
# Icons: the template deliberately carries none, because a borrowed one is worse than none. The
# adaptive-icon set for <icon-name> is installed from icons/<icon-name>/res (falling back to
# ~/app-icons/<icon-name>/res, then to the app id). With no set available a neutral placeholder is
# generated so a build can never break on a missing icon.
set -euo pipefail

CLONE="${1:?clone dir}"; PKG="${2:?pkg, e.g. gridcraft-android}"
APP_ID="${3:?app id, e.g. ai.storyteller.gridcraft}"; LABEL="${4:?app label}"
VERSION_NAME="${5:-1.0}"; ICON_NAME="${6:-}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/../templates/android-shell"
DEST="$CLONE/apps/$PKG/android"

[ -d "$TEMPLATE" ] || { echo "FAIL: no template at $TEMPLATE" >&2; exit 2; }
[ -d "$CLONE/apps" ] || { echo "FAIL: $CLONE does not look like a Craft app workspace" >&2; exit 2; }

rm -rf "$DEST"
mkdir -p "$DEST"
rsync -a --exclude '.gradle' --exclude 'build' "$TEMPLATE"/ "$DEST"/

# java package directory: ai.storyteller.gridcraft -> ai/storyteller/gridcraft
PKG_PATH="$(printf '%s' "$APP_ID" | tr '.' '/')"
mkdir -p "$DEST/app/src/main/java/$PKG_PATH"
mv "$DEST/app/src/main/java/__JAVA_PKG_PATH__/MainActivity.java" \
   "$DEST/app/src/main/java/$PKG_PATH/MainActivity.java"
rmdir "$DEST/app/src/main/java/__JAVA_PKG_PATH__"

# Substitute in every text file (skips the wrapper jar and the icon bitmaps).
while IFS= read -r -d '' f; do
  case "$f" in *.jar|*.png|*.webp|*.ico) continue ;; esac
  sed -i '' \
    -e "s|__APP_ID__|$APP_ID|g" \
    -e "s|__APP_LABEL__|$LABEL|g" \
    -e "s|__PKG__|$PKG|g" \
    -e "s|__VERSION_NAME__|$VERSION_NAME|g" \
    "$f"
done < <(find "$DEST" -type f -print0)

# The Rust crate must exist for the jniLibs source dir to be meaningful.
mkdir -p "$CLONE/apps/$PKG/jniLibs"

# ---------------------------------------------------------------- icons
RES="$DEST/app/src/main/res"
install_icons() {
  local name="${1:-$ICON_NAME}"
  [ -n "$name" ] || name="$APP_ID"
  local cand
  for cand in "$HERE/../icons/$name/res" "$HOME/app-icons/$name/res" "$HERE/../icons/$APP_ID/res" "$HOME/app-icons/$APP_ID/res"; do
    if [ -d "$cand" ]; then
      cp -R "$cand/." "$RES/"
      echo "== icons: $cand"
      return 0
    fi
  done
  # No set: emit a neutral placeholder so the manifest's @mipmap/ic_launcher still resolves.
  echo "== icons: none found for '$name' — writing a neutral placeholder" >&2
  mkdir -p "$RES/values" "$RES/drawable" "$RES/mipmap-anydpi-v26" "$RES/mipmap-anydpi"
  cat > "$RES/values/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F2937</color>
</resources>
XML
  cat > "$RES/drawable/ic_launcher_foreground.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFFFFF"
        android:pathData="M34,34h40v40h-40z" />
</vector>
XML
  for d in mipmap-anydpi-v26 mipmap-anydpi; do
    cat > "$RES/$d/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
XML
    cp "$RES/$d/ic_launcher.xml" "$RES/$d/ic_launcher_round.xml"
  done
  return 0
}
install_icons

echo "== shell: $DEST"
echo "== app id: $APP_ID   label: $LABEL   versionName: $VERSION_NAME"
grep -n "applicationId\|namespace" "$DEST/app/build.gradle"
grep -n "package " "$DEST/app/src/main/java/$PKG_PATH/MainActivity.java"
echo "== res:"; find "$RES" -type f | sed "s|$RES/||" | sort
