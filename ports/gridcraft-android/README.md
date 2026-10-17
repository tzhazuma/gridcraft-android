# gridcraft-android：把 GridCraft 接到 Android

上游 `storytold/gridcraft` 没有任何移动端代码。这里给出「加一个平台 crate」的最小集成路径——和上游
`apps/gridcraft-web` 的做法一一对应：新建一个 L6 app crate，复用 `gridcraft-engine` +
`gridcraft-ui-egui`，只补平台壳。

## 1. 放进仓库

```bash
cp -R ports/gridcraft-android <gridcraft-clone>/apps/gridcraft-android
```

根 `Cargo.toml` **不用改**：workspace 成员是 `apps/*` 通配。

只有跑 `cargo xtask ci` 时才需要在 `xtask/src/main.rs` 的 `LAYERS` 表里加一行
`("android", 6),`（`short()` 会把 `gridcraft-android` 归为 `android`）。不加密不影响编译。

## 2. Gradle 外壳

```bash
scripts/make-shell.sh <gridcraft-clone> gridcraft-android \
    ai.storyteller.gridcraft GridCraft 0.7.0
```

它把 `templates/android-shell/` 镜像成 `<clone>/apps/gridcraft-android/android/`，并把
`__APP_ID__` / `__APP_LABEL__` / `__PKG__` / `__VERSION_NAME__` 替换掉。

## 3. 构建

```bash
scripts/build-so.sh  gridcraft     # → apps/gridcraft-android/jniLibs/arm64-v8a/libmain.so
scripts/build-apk.sh gridcraft     # → out/GridCraft-0.7.0-android-arm64.apk
scripts/device-smoke.sh ai.storyteller.gridcraft .MainActivity GridCraft
```

## 4. 这个 crate 做了什么

| 桌面（`apps/gridcraft`） | Android（本 crate） |
|---|---|
| `std::env::args()`（文件、`--sample`） | 无：启动即空白工作簿 |
| `config_dir()` 来自 `HOME`/`XDG_CONFIG_HOME` | `AndroidApp::internal_data_path()` |
| `rfd` 文件对话框、`arboard` 剪贴板 | 未接：`Services` 保持默认（见下） |
| `sys-locale` 界面语言 | 英文 |
| `craft-print` 打印机 | 无 |
| 桌面尺寸 UI（1440×900、悬停菜单） | `TouchShell` 放大触摸目标 |
| — | `/system/fonts` 的 CJK 回退字体 |

引擎、ribbon、grid、主题**一行未改**，手机走的是和桌面完全相同的代码路径。

## 5. 已知缺口（首版必然缺的东西）

- **文件打开/保存**：`rfd` 没有 Android 后端，`Services` 里 `pick_open` / `pick_save` /
  `pick_picture` 全是 `None`。UI 对 `None` 有降级路径（不崩，只是选择器不可用）。要真正可用得写
  SAF（`ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT`）桥，参考 filmcraft 的 `SafBridge.java`。
- **剪贴板**：`arboard` 无 Android 后端，`copy_html`/`paste_*` 为 `None`。GridCraft 会退到自己的
  内部剪贴板；跨应用粘贴需要 JNI 调 `ClipboardManager`。
- **触屏 UI**：ribbon 有几十个小组件，是按鼠标设计的。`TouchShell` 只把命中目标放大到 40pt，
  真正的触控布局（折叠 ribbon、底部工具条、长按菜单）是产品级工作量。
- **中文界面**：`sys-locale` 在 Android 上能用（走 libc `setlocale`），但 `Language::system()`
  未接；默认英文。CJK **字形**已经有 `/system/fonts` 回退，中文单元格内容能正常显示。
- **`unsafe_code` 政策**：上游 workspace 是 `forbid`。本 crate 用 `deny` + 入口处
  `#[allow(unsafe_code)]`（`#[unsafe(no_mangle)]` 需要），与 `crates/platform` 的既有先例一致。
  上游若合并，建议同步更新 ADR 0001。
