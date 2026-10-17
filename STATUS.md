# ArtCraft → Android arm64-v8a：试点移植状态

工作区 `~/artcraft-android/`。目标：把 `github.com/storytold` 的 Craft 系列（纯 Rust + egui/eframe）
移植到 Android arm64-v8a，先打通一个试点，再把方法复制到其余应用。

**试点：GridCraft v0.7.0**（`storytold/gridcraft`，Excel 风格电子表格）。
**第二个目标：craft-launcher v0.4.1**（ArtCraft Launcher，套件启动器）。

上游 commit：`f1894c6da64d4326022ae644c767581816a23c2c`

---

## 0. 一句话结论

**两个移植的编译链路都已完全打通**，各自有独立 GitHub 仓库和带 APK 的 release：

| 移植 | `libmain.so` | APK | 仓库 / release |
|---|---|---|---|
| **GridCraft 0.7.0** | 34,719,928 B | **31,046,808 B** | [`tzhazuma/gridcraft-android`](https://github.com/tzhazuma/gridcraft-android) · [v0.7.0](https://github.com/tzhazuma/gridcraft-android/releases/tag/v0.7.0) |
| **ArtCraft Launcher 0.4.1** | 21,720,624 B | **23,547,020 B** | [`tzhazuma/craft-launcher-android`](https://github.com/tzhazuma/craft-launcher-android) · [v0.4.1](https://github.com/tzhazuma/craft-launcher-android/releases/tag/v0.4.1) |

两者都是 0 error、`zipalign -c -P 16` 通过、`aapt2` 校验通过、LOAD 段 0x4000 对齐。
启动器的下载地址已改为指向 `tzhazuma/<app>-android`（见 §9 与
[docs/LAUNCHER-DOWNLOAD-URLS.md](docs/LAUNCHER-DOWNLOAD-URLS.md)），并有测试证明。

**唯一未完成的环节是真机安装截图——设备处于锁屏，vivo 会静默丢弃安装，而解锁手势（双指上滑）
无法用 adb 合成。见 §6。**

---

## 1. 环境事实（与任务简报不同，已实测修正）

| 项 | 简报说的 | 实测 |
|---|---|---|
| rustup | **没有**，缺 `aarch64-linux-android` std | **本来就有**。默认 toolchain 是 `nightly`(1.91) 且**确实**缺该 target；但 `stable` = **cargo/rustc 1.99.0**，**已经装了 `aarch64-linux-android` std**。→ 全流程只要 `cargo +stable`，**不需要安装任何东西** |
| cargo-ndk | 4.1.2 已装 | ✅ `cargo-ndk 4.1.2` |
| NDK | `~/Library/Android/sdk/ndk/28.2.13676358` | ✅（r28 是 16 KB 页对齐的前提） |
| adb | 未提 | `~/Library/Android/sdk/platform-tools/adb`，**不在非交互 shell 的 PATH 里** |
| gh | 「已以 tzhazuma 登录」 | ✅ 在 `/opt/homebrew/bin/gh`，**也不在 PATH 里** |
| JDK | 未提 | 系统 `java` 是 **27**，AGP 9.1 **会拒绝**。必须 `JAVA_HOME=/opt/homebrew/opt/openjdk@21` |
| Gradle | 未提 | `gradle-9.3.1` 已在 `~/.gradle/wrapper/dists`，**离线可用**，无需下载 |
| python3 | 坏的 | ✅ 确认；脚本里一律 `/usr/bin/python3` |
| 内存 | 未提 | **18 GB，可用常年在 100 MB 量级**。并发 rustc 会 OOM → 见 §4 的构建锁 |

验证命令：

```bash
rustc +stable --print target-libdir --target aarch64-linux-android
# /Users/azuma/.rustup/toolchains/stable-aarch64-apple-darwin/lib/rustlib/aarch64-linux-android/lib
```

---

## 2. 完整可复现步骤

```bash
cd ~/artcraft-android
source scripts/env.sh && artcraft_check_env      # 缺什么会明确报出来

# 1) 上游（浅克隆即可）
mkdir -p src && git clone --depth 1 https://github.com/storytold/gridcraft.git src/gridcraft

# 2) Rust cdylib → apps/gridcraft-android/jniLibs/arm64-v8a/libmain.so
scripts/build-so.sh gridcraft

# 3) Gradle 外壳（模板 + 该 app 的图标集）
scripts/make-shell.sh "$PWD/src/gridcraft" gridcraft-android \
    ai.storyteller.gridcraft GridCraft 0.7.0 gridcraft

# 4) APK → out/GridCraft-0.7.0-android-arm64.apk
scripts/build-apk.sh gridcraft

# 5) 真机（需要设备解锁，见 §6）
scripts/device-smoke.sh ai.storyteller.gridcraft .MainActivity GridCraft
```

`scripts/env.sh` 里 export 的关键变量（不 source 它必然踩坑）：

```bash
export PATH="$HOME/.cargo/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:/opt/homebrew/bin:$PATH"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export CARGO_BUILD_JOBS=4          # 18 GB 内存下的上限
```

---

## 3. 产物与证据

| 产物 | 路径 | 大小 | SHA-256 |
|---|---|---|---|
| GridCraft Rust 动态库 | `src/gridcraft/apps/gridcraft-android/jniLibs/arm64-v8a/libmain.so` | 34,719,928 B | `9d42492d7e29776cf81382d98c2d5955915d1b8f1c51adabe6ec2121227b5a38` |
| GridCraft APK | `out/GridCraft-0.7.0-android-arm64.apk` | 31,046,808 B | `e2844f5c4ae92cac595fe139be586e13af2662715cf23afb7bdde055f11a431a` |
| Launcher Rust 动态库 | `src/craft-launcher/apps/craft-launcher-android/jniLibs/arm64-v8a/libmain.so` | 21,720,624 B | — |
| Launcher APK | `out/ArtCraftLauncher-0.4.1-android-arm64.apk` | 23,547,020 B | `f3e3dc339ad37c02f03f063e53c0f07084ab1bb80a6bf5b47d46a49440283437` |

```
$ cargo +stable ndk -t arm64-v8a build --release -p gridcraft-android
== cargo exit code: 0
== artifact: .../libmain.so (34719928 bytes)          # 0 error, 0 warning

$ aapt2 dump badging out/GridCraft-0.7.0-android-arm64.apk
package: name='ai.storyteller.gridcraft' versionCode='1' versionName='0.7.0' ...
targetSdkVersion:'35'
application-label:'GridCraft'
launchable-activity: name='ai.storyteller.gridcraft.MainActivity'
native-code: 'arm64-v8a'
application-icon-480:'res/BW.xml'                      # 矢量 adaptive icon

$ zipalign -c -P 16 -v 4 out/GridCraft-0.7.0-android-arm64.apk
== zipalign -P 16: OK (16 KB page aligned)

$ llvm-readelf -lW libmain.so | grep LOAD
  LOAD 0x000000  0x0000000000000000 ... 0x66ddb0  R   0x4000
  LOAD 0x66ddb0  0x0000000000671db0 ... 0x108c150 R E 0x4000
  LOAD 0x16f9f00 0x0000000001701f00 ... 0x0b3988  RW  0x4000
  LOAD 0x17ad890 0x00000000017b9890 ... 0x001d20  RW  0x4000
```

### ArtCraft Launcher 0.4.1

```
$ cargo +stable ndk -t arm64-v8a build --release -p artcraft-launcher-android
== cargo exit code: 0
== artifact: .../libmain.so (21720624 bytes)          # 0 error

$ aapt2 dump badging out/ArtCraftLauncher-0.4.1-android-arm64.apk
package: name='ai.storyteller.artcraftlauncher' versionCode='1' versionName='0.4.1' ...
targetSdkVersion:'35'
application-label:'ArtCraft Launcher'
launchable-activity: name='ai.storyteller.artcraftlauncher.MainActivity'
native-code: 'arm64-v8a'
application-icon-480:'res/BW.xml'

$ zipalign -c -P 16 -v 4 out/ArtCraftLauncher-0.4.1-android-arm64.apk
== zipalign -P 16: OK (16 KB page aligned)

$ strings -a lib/arm64-v8a/libmain.so | grep -c tzhazuma
1                                                      # 我们自己的 release owner 编进了产物
```

> **Android 包名与上游 bundle id 不同**：上游是 `ai.storyteller.artcraft-launcher`，连字符在
> Android 的 `applicationId` / Java 包里**不合法**（AGP 报
> `Namespace ... is not a valid Java package name as 'artcraft-launcher' is not a valid Java identifier`）。
> Android 包名去掉连字符：**`ai.storyteller.artcraftlauncher`**。这是唯一一处移植版与上游标识
> 不同的地方，记在 `scripts/env.sh` 的 `artcraft_app_id()` 里。

### 上游补丁可复现性

```bash
$ git clone --depth 1 https://github.com/storytold/craft-launcher.git cl && cd cl
$ git apply --check .../0001-release-owner-override.patch
PATCH APPLIES CLEANLY to pristine upstream
```

---

## 4. 方法：加一个平台 crate，不动上游

上游已经为多平台准备好像素的抽象缝——每个 app 都有 `apps/<app>-web`（WASM），所以代码本身平台
抽象是干净的。移植照抄这个先例：**新建一个 L6 app crate**，复用 engine + ui-egui，只补平台壳。

```
ports/gridcraft-android/          ← 移植源码（source of truth）
  Cargo.toml                      [lib] name="main" crate-type=["cdylib"]
  src/lib.rs                      android_main + TouchShell + 字体 + 偏好
  README.md                       集成步骤 + 已知缺口
```

`build-so.sh` 每次构建前把 `ports/<pkg>/` **rsync 覆盖**进克隆的 `apps/<pkg>/`，所以移植源码永远
是权威，克隆里手改的东西不会静默生效。

### 关键实现点

1. **入口**（edition 2024 下 `#[no_mangle]` 必须写成 `#[unsafe(no_mangle)]`）：

```rust
#[allow(unsafe_code)]                       // 上游 workspace 是 unsafe_code="forbid"，
#[unsafe(no_mangle)]                        // 本 crate 用 deny + 入口处 allow，
fn android_main(app: AndroidApp) {          // 与 crates/platform 的既有先例一致
    let options = eframe::NativeOptions { android_app: Some(app), ..Default::default() };
    eframe::run_native("GridCraft", options, Box::new(|cc| Ok(Box::new(TouchShell::new(...))))).unwrap();
}
```

2. **eframe features 必须按目标拆分**：
   `["default_fonts","wgpu","android-game-activity"]`
   - `accesskit` + `android-native-activity` 是 eframe 的硬 `compile_error!`；
   - NativeActivity 没有软键盘/IME，ribbon + 公式栏这种要打字的 app **必须 GameActivity**。
   - 不要直接依赖 `android-activity`，用 winit 再导出的
     `winit::platform::android::activity::AndroidApp`。

3. **Gradle 外壳**：`templates/android-shell/`（AGP 9.1.0 / Gradle 9.3.1 / JDK 21 / minSdk 31 /
   compileSdk 35）。`app/build.gradle` 的 `jniLibs.srcDirs = ['../../jniLibs']` 指向 `cargo ndk -o`
   的输出目录。release 用 **debug 签名**，这样 release APK 能直接 `adb install`。
   `MainActivity extends GameActivity` + `static { System.loadLibrary("main"); }`，
   manifest 里 `android.app.lib_name = "main"` 必须与 `[lib] name = "main"` 一致。

4. **构建锁**（本机特有）：18 GB 内存 + 多个 agent 并发 cargo 会 OOM。`scripts/build-lock.sh`
   用 `/usr/bin/python3` 的 `fcntl.flock`（macOS 没有 `flock(1)`）把整机构建串行化，并配
   `CARGO_BUILD_JOBS=4`。

5. **剥掉构建机身份**：`RUSTFLAGS="--remap-path-prefix=$HOME=/build --remap-path-prefix=<clone>=/src"`。
   不加的话 rustc 会把 `/Users/azuma/...` 的 panic 路径烧进二进制，任何人 `strings libmain.so`
   都能看到（实测每包 632–1221 处）。

---

## 5. 踩坑清单

| # | 坑 | 现象 | 处理 |
|---|---|---|---|
| 1 | 默认 toolchain 是 nightly | `cargo build --target aarch64-linux-android` 报找不到 std | 全程 `cargo +stable` |
| 2 | 系统 java 是 27 | AGP 9.1 直接拒绝 | `JAVA_HOME=/opt/homebrew/opt/openjdk@21` |
| 3 | adb / gh 不在 PATH | `command not found` | 脚本显式 export |
| 4 | `bash -c "..."` 里嵌引号 | 外层展开把 PATH 搅坏，连 `cc` 都找不到 | 构建脚本用 **quoted heredoc + 占位符 + sed** 生成，绝不用 `bash -c` 传命令串 |
| 5 | 管道吃掉退出码 | `cargo ... \| tail` 让失败看起来成功 | 绝不把构建管道进 `tail`；`build-so.sh` 自己 `exit $rc` |
| 6 | `/sdcard` 安装 | SELinux 拒绝：system_server 读不了 fuse | `adb push` 到 **`/data/local/tmp/`** 再 `pm install -r -t` |
| 7 | 锁屏时安装 | `pm install` **无任何输出**，`lastUpdateTime` 不变，静默丢弃 | 装前查 `dumpsys window \| grep mDreamingLockscreen`；见 §6 |
| 8 | 无线调试端口漂移 | `adb devices` 空 | 先试 `<IP>:5555`（经典 adbd 端口，本会话两次救场），再 `adb mdns services \| grep _adb-tls-connect` |
| 9 | 大 APK 走无线 adb | `adb install` 永久挂住（包其实已装上） | 所有 adb 调用加 `timeout`；超时后改用「查包名是否存在」判定 |
| 10 | `mipmap-*dpi/*.webp` 继承自别的 app | 非 FilmCraft 的 app 显示 FilmCraft 图标 | 模板不带图标；每个 app 装自己的矢量集 |
| 11 | egui 默认字体无 CJK | 中文渲染成方块 | 运行时挂 `/system/fonts/NotoSansCJK-Regular.ttc` 到 family 末尾 |
| 12 | `dirs` 在 Android 返回 `None` | `Paths::new()` 掉进 `temp_dir()`（Android app 写不了 `/tmp`） | 给 native crate 加 `Paths::set_root()`，壳在 backend 构造前注入 `internal_data_path()` |
| 13 | `.gitignore` 里没锚定的 `src/` | 它同时匹配 `ports/<app>-android/src/` 和 `templates/.../app/src/`，**第一次 push 因此漏掉了 port 的 lib.rs 和模板的 manifest/MainActivity** | 一律写 `/src/`（带前导斜杠）；push 后 `git ls-files` 核对关键文件在不在 |
| 14 | 上游 bundle id 带连字符 | AGP 报 `Namespace 'ai.storyteller.artcraft-launcher' is not a valid Java package name` | Android 包名去连字符 → `ai.storyteller.artcraftlauncher` |
| 15 | 目录名 ≠ crate 名 | `cargo ndk -p craft-launcher-android` 报 `unknown package`（crate 实际叫 `artcraft-launcher-android`） | `build-so.sh` 从 `ports/<pkg>/Cargo.toml` 读 `[package] name` |

---

## 6. 阻塞项：真机锁屏（需要人类）

设备 **vivo PA2573 / Android 16 / arm64-v8a**，`10.20.102.152:5555`。

```
$ adb -s 10.20.102.152:5555 shell dumpsys window | grep mDreamingLockscreen
    mShowingDream=false mDreamingLockscreen=true
$ adb -s 10.20.102.152:5555 shell dumpsys power | grep mWakefulness=
  mWakefulness=Asleep
```

- vivo 在**锁屏**时会**静默丢弃** `pm install`（无输出、`lastUpdateTime` 不变），所以装不上。
- 解锁手势是**双指上滑**，`adb shell input swipe` 合成不出来。
- `input keyevent KEYCODE_WAKEUP` 只能把 `mWakefulness` 变成 `Awake`，锁屏依旧在。

**请人类解锁手机并保持亮屏**，然后：

```bash
cd ~/artcraft-android
scripts/device-smoke.sh ai.storyteller.gridcraft .MainActivity GridCraft gridcraft-real
# 期望：PASS: launched, no crash / PASS: activity is focused
#       shots/gridcraft-real.png
```

`device-smoke.sh` 检测到锁屏会**直接报「HUMAN ACTION REQUIRED」并 exit 5**，不会空转重试。

旁证：设备上已装有 `ai.storyteller.{filmcraft,lightcraft,photocraft,effectcraft,printcraft}`
五个包，说明「push → pm install」这条路在本机是走通过的。

---

## 7. 还没做的 / 已知缺口

### GridCraft 首版缺的
- **文件打开/保存**：`rfd` 没有 Android 后端，`Services` 的 `pick_open`/`pick_save`/`pick_picture`
  全是 `None`。UI 对 `None` 有降级路径（不崩，只是选择器不可用）。要真可用得写 SAF 桥
  （`ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT`）。
- **剪贴板**：`arboard` 无 Android 后端；跨应用粘贴需要 JNI 调 `ClipboardManager`。
- **触屏布局**：ribbon 是按鼠标设计的。`TouchShell` 只把命中目标放大到 40 pt（
  `interact_size = 40×40`、`show_tooltips_only_when_still = true`）；真正的触控布局是产品级工作量。
- **中文界面**：CJK **字形**已回退，中文单元格能正常显示；界面语言仍是英文。

### craft-launcher 首版缺的
`artcraft-launcher-ui-egui`（真正的 UI）和 `artcraft-launcher-native`（真正的下载/安装后端，
含 ureq + rustls）都是**上游原样复用**，两者 `check --target aarch64-linux-android` 0 error，
`libmain.so` 已产出。三处运行时适配都在补丁里解决了：

1. **`rustls-platform-verifier 0.7.1` 在 Android 需要额外 Kotlin 组件**，并且要从 GitHub Packages
   拉 Maven 包（`org.rustls:rustls-platform-verifier-android`）。**已绕开**：`crates/native/src/http.rs`
   那唯一一处 `RootCerts::PlatformVerifier` 在 Android 上改成 `RootCerts::new_with_certs(...)`
   读 `/system/etc/security/cacerts`（设备上实测 **149 个** `*.0`）。仍是「OS 决定信任什么」，
   且不引入新的 Gradle/Maven 依赖。**代价**：放弃吊销检查（CRL/OCSP）和用户安装的根证书——
   对 GitHub 的证书没影响，对企业 MITM 代理有影响。
2. **`dirs` 在 Android 返回 `None`** → 补丁给 native crate 加了 `Paths::set_root()`，
   移植壳在 backend 构造**之前**注入 `AndroidApp::internal_data_path()`。
3. 桌面壳的 `notify-rust` / `rfd` / `tray-icon` / `zbus` 在 Android 上不需要 cfg 掉：因为移植是
   **新建 crate**，这些依赖根本不会被引入，`apps/artcraft-launcher` 一行都不用改。
   `single_instance`（loopback TCP 47413）原样保留，Android 沙盒内可用。

仍然没做的（都是产品级工作量，不影响「能起来」）：
- **通知**：只有 logcat，没有真的系统通知（要 JNI 桥到 `NotificationManager`）。
- **文件夹选择**：`pick_folder` 是 `None`，`install_locations.root` 改不了（要 SAF）。
- **安装语义**：`NativeBackend` 装的是**桌面包**（`.dmg`/`.msi`/`.AppImage`/`.deb`）。Android 上
  它只应该装**我们自己的 APK release**——这需要新增一个 Android 的 `PackageKind` 并走
  `PackageInstaller` Intent。**这一层没做**，所以现在启动器会显示「没有适合这个平台的包」，
  而不会去下载一个装不了的桌面包（这正是我们要的行为，但还不是完整的安装流程）。

### 其他
- ✅ 每个移植有**独立 GitHub 仓库**并带 release（见 §8）。
- ✅ craft-launcher 的下载地址指向我们自己的 release（见 §9）。

---

## 8. 仓库与发布

命名跟已有惯例（`tzhazuma/freecad-android`、`blender-android`、`octave-android`、`dsh-android`）：

| 仓库 | 内容 | release |
|---|---|---|
| [`tzhazuma/gridcraft-android`](https://github.com/tzhazuma/gridcraft-android) | GridCraft 移植 + 共享工具链（scripts/templates/icons/docs） | [v0.7.0](https://github.com/tzhazuma/gridcraft-android/releases/tag/v0.7.0) — `GridCraft-0.7.0-android-arm64.apk` |
| [`tzhazuma/craft-launcher-android`](https://github.com/tzhazuma/craft-launcher-android) | ArtCraft Launcher 移植（port crate + 上游补丁 + 自己的脚本副本） | [v0.4.1](https://github.com/tzhazuma/craft-launcher-android/releases/tag/v0.4.1) — `ArtCraftLauncher-0.4.1-android-arm64.apk` |

APK 走 **GitHub Releases**，不进 git 历史。每个 per-port 仓库的暂存树在
`dist-repos/<repo>/`（已 gitignore），由 workspace 的 `ports/`、`scripts/`、`templates/`、`icons/`
拷贝而成。

**每个 release 必须带一个 `SHA256SUMS.txt`**（标准 `sha256sum` 格式，文件名叫这个，不能用
`gh release upload <file>#SHA256SUMS.txt` 改 label —— 那只改显示名，URL 路径还是原名）。
理由：GitHub API 被限额时，启动器走 release 页面回退路径，读
`https://github.com/<repo>/releases/download/<tag>/SHA256SUMS.txt` 来重建 release；没有这个文件
它会认为「这个 app 没有 release」。

端到端验证（下载线上资产，和 `SHA256SUMS.txt`、和本地构建三方比对）：

```
$ curl -sSL -o GridCraft.apk .../releases/download/v0.7.0/GridCraft-0.7.0-android-arm64.apk
http=200 bytes=31046808
downloaded : e2844f5c4ae92cac595fe139be586e13af2662715cf23afb7bdde055f11a431a
SHA256SUMS : e2844f5c4ae92cac595fe139be586e13af2662715cf23afb7bdde055f11a431a
local build: e2844f5c4ae92cac595fe139be586e13af2662715cf23afb7bdde055f11a431a
MATCH ✅  the launcher's checksum verification would pass
```

---

## 9. craft-launcher 的下载地址

启动器的下载 URL 由「某个 app 的 `owner/repo`」决定，而那个字符串**只在一个函数里产生**：

```
crates/core/src/release.rs:64    format!("https://github.com/{repo}/releases/download/")
crates/core/src/feed.rs:191      format!("https://github.com/{repo}/releases/")
crates/native/src/backend.rs:766 fn feed_repo(feed, app) -> String      ← 唯一接缝
```

改动（`ports/craft-launcher-android/upstream/0001-release-owner-override.patch`）：

- `catalog.rs` 新增 `RELEASE_OWNER: Option<&str> = Some("tzhazuma")` 与
  `CraftApp::release_repo()` → `tzhazuma/<id>-android`；
- `feed_repo()` 在设置了覆盖时直接返回它，**并且故意不咨询 release feed**（feed 描述上游桌面版，
  跟着它的 `repo_renames` 会把查询拉回一个本构建不该安装的仓库）；
- `repo_url()` / `releases_url()` / `website()` **保持不变**，仍指向上游——它们是文档链接。

验证：`cargo +stable test -p artcraft-launcher-core --lib` → **34 passed; 0 failed**，其中新增的
`a_port_looks_releases_up_in_its_own_repositories` 对全部 13 个 app 断言了新的下载前缀与未变的
文档链接；`crates/native/src/backend.rs` 里另有 `a_port_asks_its_own_repositories_for_releases`
走真正被调用的 `feed_repo()`（Android target 上 `check --tests` 通过）。

完整链路、13 个 app 的地址表和验证输出见 `docs/LAUNCHER-DOWNLOAD-URLS.md`。

---

## 10. 目录结构

```
~/artcraft-android/
├── STATUS.md                  ← 本文件
├── README.md
├── scripts/
│   ├── env.sh                 共享环境（PATH/NDK/JDK/lock/设备）
│   ├── build-lock.sh          整机构建串行化（fcntl）
│   ├── build-so.sh            <app> → libmain.so（crate 名从 ports/<pkg>/Cargo.toml 读）
│   ├── build-apk.sh           <app> → out/<Label>-<ver>-android-arm64.apk
│   ├── make-shell.sh          生成 Gradle 外壳 + 装该 app 的图标
│   └── device-smoke.sh        装机/启动/logcat/截图（含锁屏门禁）
├── templates/android-shell/   Gradle 骨架（AGP 9.1.0 / Gradle 9.3.1 / JDK 21）
├── icons/<app>/res/           每个 app 的矢量 adaptive icon（来自 icon-designer）
├── ports/<app>-android/       移植源码（source of truth）
│   └── craft-launcher-android/upstream/*.patch   需要的上游改动
├── docs/LAUNCHER-DOWNLOAD-URLS.md                下载地址链路 + 证明
├── dist-repos/<repo>/         per-port 仓库暂存树（gitignore 掉）
├── src/<app>/                 上游浅克隆（gitignore 掉）
├── out/                       APK
├── shots/                     真机截图
└── logs/                      构建日志
```
