# craft-launcher 的下载地址：指向我们自己的移植仓库

## 目标

ArtCraft Launcher 的下载地址必须指向**我们自己移植的 GitHub release**，而不是上游
`storytold/*` 的桌面版 release。否则启动器会去拿 `.dmg` / `.msi` / `.AppImage`——那些包在
Android 上装不了，也没意义。

## 上游的地址是怎么拼出来的

只有一条链路，全部由「某个 app 的 `owner/repo`」决定：

| 位置 | 代码 | 作用 |
|---|---|---|
| `crates/core/src/release.rs:64` | `format!("https://github.com/{repo}/releases/download/")` | **下载 URL 前缀**，也是 `SHA256SUMS.txt` 的前缀 |
| `crates/core/src/feed.rs:191` | `format!("https://github.com/{repo}/releases/")` | release 页面（API 限额时的回退） |
| `crates/core/src/release.rs:102` | `format!("https://github.com/{repo}/releases")` | `/releases/latest` 重定向探测 |
| `crates/core/src/catalog.rs` | `pub const SUITE: [CraftApp; 13]` 的 `repo` 字段 | 上游值：`storytold/<id>` |

而 `repo` 这个字符串**只在两个地方**被决定，两个都经过同一个函数：

```
crates/native/src/backend.rs:156   s.cached(&feed_repo(feed.as_ref(), app), pre)
crates/native/src/backend.rs:737   let repo = feed_repo(feed, app);
crates/native/src/backend.rs:766   fn feed_repo(feed, app) -> String
```

`feed_repo()` 的结果一路传进 `ReleaseSource::latest(repo, …)` → `release::download_prefix(repo)`
→ 资产 URL 与校验和。所以**改这一个函数就能整体搬走**，不会出现「release 列表来自 A、下载
URL 来自 B」的半吊子状态。

## 改动（`ports/craft-launcher-android/upstream/0001-release-owner-override.patch`）

### 1. `crates/core/src/catalog.rs`：新增 owner 覆盖

```rust
pub const RELEASE_OWNER: Option<&str> = Some("tzhazuma");

impl CraftApp {
    /// 每个 release 查询、资产 URL、校验和用的仓库。
    pub fn release_repo(&self) -> String {
        match RELEASE_OWNER {
            Some(owner) => format!("{owner}/{}-android", self.id),
            None => self.repo.to_string(),
        }
    }
}
```

`None` 就是上游行为，release 构建保持原样。

### 2. `crates/native/src/backend.rs`：唯一的接缝改用 `release_repo()`

```rust
fn feed_repo(feed: Option<&Feed>, app: &CraftApp) -> String {
    if artcraft_launcher_core::catalog::RELEASE_OWNER.is_some() {
        return app.release_repo();   // 移植版：自己的仓库，且不再咨询 feed
    }
    feed.map_or_else(|| app.repo.to_string(), |f| f.repo_for(app))
}
```

设置了覆盖时**故意不咨询 release feed**：feed 描述的是上游的桌面版 release，跟着它的
`repo_renames` 走会把查询拉回一个本构建不该安装的仓库。

### 3. 故意**没有**改的东西

`repo_url()` / `releases_url()` / `website()` 仍然指向上游。它们是**文档链接**（详情抽屉里的
「GitHub repository」「All releases」「Website」），源码本来就在上游，把用户引到上游是对的。
只有「查询 release / 下载 / 校验和」搬走。

## 验证

```bash
cd src/craft-launcher
cargo +stable test -p artcraft-launcher-core --lib
```

新增的测试 `catalog::tests::a_port_looks_releases_up_in_its_own_repositories` 断言：

- 对 `SUITE` 里**全部 13 个** app：`release_repo()` == `tzhazuma/<id>-android`；
- 对全部 13 个 app：`repo_url()` / `releases_url()` 仍以 `https://github.com/storytold/` 开头，
  `website()` 仍是 `https://getartcraft.com/apps/<id>`；
- `release::download_prefix(gridcraft.release_repo())` ==
  `https://github.com/tzhazuma/gridcraft-android/releases/download/`。

实测结果：

```
running 1 test
test catalog::tests::a_port_looks_releases_up_in_its_own_repositories ... ok

test result: ok. 34 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out
```

`crates/native/src/backend.rs` 里另有一个 `a_port_asks_its_own_repositories_for_releases`，走的是
真正被调用的 `feed_repo()`（不是测试替身），断言解析出的仓库和下载前缀都不含 `storytold/`。
它只能在 Android target 上编译——上游 `crates/native/src/self_update.rs` 在 macOS 上的测试代码
**本来就是坏的**（`install_dmg` 参数个数对不上，E0061，已用 `git stash` 在 pristine HEAD 上确认
与本次改动无关）：

```bash
# macOS 上（既有问题，与本次改动无关）
cargo +stable check --tests -p artcraft-launcher-native
#   error[E0061]: this function takes 7 arguments but 6 arguments were supplied  (self_update.rs:184/374)

# Android 上（本次改动的目标平台，测试代码全绿）
cargo +stable ndk -t arm64-v8a check --tests -p artcraft-launcher-native
#   Finished `dev` profile ... in 2.59s
```

## 每个 app 对应的仓库

| app id | 移植仓库 | release 下载前缀 |
|---|---|---|
| `photocraft` | `tzhazuma/photocraft-android` | `https://github.com/tzhazuma/photocraft-android/releases/download/` |
| `vectorcraft` | `tzhazuma/vectorcraft-android` | … |
| `filmcraft` | `tzhazuma/filmcraft-android` | … |
| `lightcraft` | `tzhazuma/lightcraft-android` | … |
| `effectcraft` | `tzhazuma/effectcraft-android` | … |
| `pdfcraft` | `tzhazuma/pdfcraft-android` | …（`id` 是 `pdfcraft`，资产 stem 也可能是 `printcraft`） |
| `designcraft` | `tzhazuma/designcraft-android` | … |
| `figcraft` | `tzhazuma/figcraft-android` | … |
| `wordcraft` | `tzhazuma/wordcraft-android` | … |
| `soundcraft` | `tzhazuma/soundcraft-android` | … |
| `deckcraft` | `tzhazuma/deckcraft-android` | … |
| `cadcraft` | `tzhazuma/cadcraft-android` | … |
| `gridcraft` | `tzhazuma/gridcraft-android` | ✅ **已建仓 + 已发布 v0.7.0**，APK 31,046,808 B |

## 还没做的

- 上面 13 个移植仓库目前**只有 `gridcraft-android` 存在**。其余 12 个建仓 + 发布后，
  `release_repo()` 拼出的地址才会真正解析到资产；在那之前启动器会显示「这个 app 没有 release」，
  而不是去下载一个装不了的桌面包——这正是我们要的行为。
- `CraftApp::former_ids`（`pdfcraft` ← `printcraft`）在移植仓库命名上不适用：移植仓库一律用
  `id`。若将来某个移植仓库用了别的名字，应改 `release_repo()`，不要改 `repo`。
