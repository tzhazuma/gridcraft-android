# Per-app adaptive icons

Vector adaptive-icon sets, one directory per app id. `scripts/make-shell.sh` copies
`icons/<icon-name>/res/` into the generated Gradle project's `app/src/main/res/`, so the icon is
part of the reproducible build rather than something hand-dropped into a generated directory.

Each set is 7 files:

```
mipmap-anydpi-v26/ic_launcher.xml        <adaptive-icon> (API 26+)
mipmap-anydpi-v26/ic_launcher_round.xml
mipmap-anydpi/ic_launcher.xml            plain <vector> legacy fallback (valid below API 26 too)
mipmap-anydpi/ic_launcher_round.xml
drawable/ic_launcher_foreground.xml      vector foreground layer
drawable/ic_launcher_monochrome.xml      Android 13+ themed-icon layer
values/ic_launcher_background.xml
```

The `<monochrome>` layer is referenced by the adaptive icon, so `drawable/ic_launcher_monochrome.xml`
must be copied along with it or the resource link fails. `make-shell.sh` copies the whole `res/`
tree, so this is automatic.

Icon artwork by the `icon-designer` teammate (shared task-7). Not derived from upstream's raster
icons.
