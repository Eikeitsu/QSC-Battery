# 构建与发布说明

面向维护者。用户文档请看 [`docs/`](../docs/)（VitePress → GitHub Pages）。

当前产品为独立演进的 **充电控制**（模块 + WebUI + 伴侣 APP + qscd），构建产物面向本仓库发布通道。

## 仓库结构

```text
webui/                  # WebUI 源码（Vue 3 + Vite + TypeScript）
module/                 # Magisk 模块本体
  webroot/              # WebUI 构建产物
  apk/                  # 可选内嵌伴侣 APK
native/qscd/            # 事件守护 Rust
native/qscd-c/          # 事件守护 C
app/                    # 伴侣 APP（Compose）
archives/               # 旧版 WebUI 快照（不打包）
tooling/scripts/        # 构建脚本
docs/                   # VitePress 用户文档
```

## 本地命令

```bash
npm install
npm run prepare           # 启用 husky（install 后一般会自动跑）
npm run dev:web           # Vite 开发预览 webui/
npm run build:web         # Vite 构建 → .build/webroot，并同步到 module/webroot
npm run build:native      # 交叉编译 native/qscd → module/bin/qscd-arm64|arm（缺 cargo/NDK 则跳过）
npm run build:native:c    # 交叉编译 native/qscd-c → module/bin/qscdc-arm64|arm（缺 NDK 则跳过）
npm run package:module    # 打 Magisk zip（webroot 缺失或过期会先 build:web）
npm run package:module:all # 打 5 个变体包：full / rust / c / sh / lite
npm run build:module      # 强制 build:web + package:module
npm run build:module:all  # 强制 build:web + 5 个变体包
npm run check             # typecheck + 全量 lint + prettier check
npm run lint              # eslint + stylelint + markdownlint + shellcheck
npm run format            # prettier 写回
npm run dev:docs          # 文档预览
npm run build:docs        # 构建文档站点
```

### Lint 矩阵

| 命令               | 覆盖                                                             |
| ------------------ | ---------------------------------------------------------------- |
| `lint:js`          | `webui` Vue/TS、`tooling` 脚本、VitePress 配置                   |
| `lint:style`       | `webui` SCSS / Vue `<style>`（Stylelint）                        |
| `lint:md`          | Markdown（markdownlint-cli2）                                    |
| `lint:shell`       | `module/**/*.sh`（shellcheck；本机未安装则跳过，CI 强制）        |
| husky `commit-msg` | Conventional Commits（commitlint）                               |
| husky `pre-commit` | lint-staged：只处理**暂存文件**（eslint / stylelint / prettier） |
| husky `pre-push`   | `npm run check`（全量；部分 GUI / `--no-verify` 不会跑）         |

提交被拦或 CI 红了时：

1. 不要用 `git commit --no-verify` / `git push --no-verify` 绕过
2. 不要设环境变量 `HUSKY=0`
3. 本地先：`npm run format` → `npm run check`
4. 钩子未生效时：在仓库根目录 `npm run prepare`，确认 `git config core.hooksPath` 为 `.husky/_`

## 原生守护（Rust 为主，C 版已冻结）

维护策略：**新功能只加在 Rust 版**。C 版冻结在现有的轻量能力
（`wait-event` / `probe` / `selftest`）上，只修 bug、不再跟进新子命令——
两版逐字对齐的要求会让每个新子命令都得写两遍，代价压过收益。

因此模块侧调用任何新子命令都必须能优雅退化：约定「未知子命令退出 2」，
调用方据此回退到 `wait-event`、`ps` 或纯 `sleep`。`qscd features` 用来一次性
问清装的是哪一套（C 版不认这个子命令，退出 2，即视为无扩展能力），结论缓存在
`data/qscd_features`，换二进制或重启服务时清掉重问。

Rust 版目前的扩展能力：

- `watch`：带阈值的等待，见下一节；插电状态与 shell 侧同时检查
  `online`、`present`、类型、VBUS 和 `battery/status`，兼容 MCA 停充后的 `online=0`
- `pkgs`：遍历 `/proc/<pid>/cmdline` 判断包名列表里有没有主进程在跑，
  替代 `ps -ef` 快照。退出 0=命中、1=没命中、2=不可用
- `selftest`：只读检查 netlink、事件过滤器和电源节点读取能力，支持
  `--sysfs-root DIR` 供假 sysfs 测试使用

新增子命令的硬性要求：只读、不写任何充电节点、不做停充/恢复决策。
sh 主包没有这个二进制也必须行为一致，阈值判定的唯一真理留在 shell。

## 原生事件等待器（Rust 版与 C 版双实现）

只有一个职责：阻塞在内核 `power_supply` uevent 上，让 shell 主循环在未插电时不必定时唤醒。
接收超时一次设满剩余时间，整段等待只在截止时刻醒一次——切成固定小段去复查截止时间会让唤醒次数翻十几倍，
反而比它替代的 `sleep` 更碎，而事件到达是数据就绪即返回，与超时长短无关。
两套实现（`native/qscd` = Rust + `libc`，`native/qscd-c` = 单文件 C）子命令、退出码、钳位范围逐字对齐，可互换安装。

- 子命令：`qscd wait-event <最长秒> [最短秒]`（0=有事件或到时，2=不可用）、`qscd probe`（安装自检）、`qscd selftest`（运行期只读诊断）；C 版的 `selftest` 继续用于宿主机纯函数门禁
- 它**不写任何充电节点、不做停充/恢复决策**；退出非 0 时 `lib/power_saver.sh` 会永久退回 `sleep`，所以最坏结果是退化成定时轮询
- 目标 `aarch64-linux-android`、`armv7-linux-androideabi`，API 由 `QSCD_ANDROID_API` 控制（默认 24）
- Rust 版需 `cargo` + NDK（NDK 的 clang 兼作链接器）；C 版只需 NDK clang，因此没有 Rust 工具链也能产出可用二进制
- 本机缺依赖时两个 `build:native*` 都打印跳过并退出 0；`CI=true` 或 `REQUIRE_NATIVE=1` 时视为失败
- 宿主端门禁（`Lint` 工作流，均不需要 NDK）：Rust 侧 `cargo fmt --check` + `clippy -D warnings` + `cargo test`；C 侧 `clang -Wall -Wextra -Werror` 编译后跑 `qscd selftest`
- 安装时 `customize.sh` 按 `$ARCH` 取包内候选，依 `config.conf` 的 `native_impl`（`rust` 默认 / `c` / `off`）顺序逐个跑 `probe`，第一个通过的装成 `bin/qscd`；实际启用的实现与来源记在 `data/native_impl_used`、`data/native_src`，其余候选文件删除
- 包内没有可用候选时（主包 / sh 变体），沿用上一版里 WebUI 下载好的 `bin/qscd`（由 `hot_update_preserve_paths` 带过来）；自带同实现时用自带的覆盖
- 运行期开关是 `config.conf` 的 `native_daemon`：关闭则 `qsc_ps_wait` 直接 `sleep`，不调用二进制

### 发布变体

`package-module.mjs --native=<full|rust|c|sh|lite>`；**均带后缀**，`update.json` 默认指向 `-full`：

| 变体   | 守护二进制           | WebUI | 内嵌 APK | zip 名                 | 说明                                        |
| ------ | -------------------- | ----- | -------- | ---------------------- | ------------------------------------------- |
| `full` | `qscd-*` + `qscdc-*` | 有    | 有       | `..._v<版本>-full.zip` | **在线更新默认**；按 `native_impl` 自检选用 |
| `rust` | 仅 `qscd-*`          | 有    | 有       | `..._v<版本>-rust.zip` | 只带 Rust 守护                              |
| `c`    | 仅 `qscdc-*`         | 有    | 有       | `..._v<版本>-c.zip`    | 只带 C 守护                                 |
| `sh`   | 无                   | 有    | 有       | `..._v<版本>-sh.zip`   | 无守护，可在 WebUI 按需下载                 |
| `lite` | 无                   | 无    | 无       | `..._v<版本>-lite.zip` | 体积最小；仅脚本，无界面与伴侣 APK          |

`CI=true` 或 `REQUIRE_NATIVE=1` 时，变体要求的二进制缺失即打包失败；本地缺编译器则只告警。`lite` 不构建 WebUI、不要求伴侣 APK。

### WebUI 下载守护

- 后端是 `module/bin/qscd_fetch.sh`（`status` / `install <rust|c>` / `use <rust|c>` / `remove`），输出统一 `KEY=VALUE`，前端 `webui/src/shared/api/daemon.ts` 解析
- 二进制与 `manifest.json`（含每个文件的 sha256）由 `post-release-update.sh` 发到 Pages 的 `qscd/` 下，文件名 `qscd-<rust|c>-<arm64|arm>`
- `install` 会先取 manifest、下载、比对 sha256、`chmod 0755`、跑 `probe`，任一步失败即回滚到原文件；成功后写回 `native_impl`、置 `native_daemon=1` 并重拉 `service.sh`（主循环把"等待器不可用"缓存在内存里，不重启不会生效）
- 两条工作流的原生构建统一走 `.github/actions/build-native`（装 Rust Android 目标 → `setup-ndk-clang` → 编译 Rust 与 C 两套）；换 NDK 版本或加架构只改这一处
- 包内容断言抽成 `npm run verify:zips`（`tooling/scripts/verify-module-zips.mjs`），打包与发版两条工作流共用，本地全量构建后也能直接跑。它按 `module.prop` 的版本号只挑本次构建的包（`release/` 常年堆着历史发布），顺带用 `verifyUnixZip` 校验 CRC 与本地头。原生二进制的缺失判定沿用 `build-native*.mjs` 的约定：CI 或 `REQUIRE_NATIVE=1` 时缺即失败，本地无 NDK 时只提示
- CI 装 NDK 走 `.github/actions/setup-ndk-clang`：**不要**给 `nttld/setup-ndk` 开 `local-cache`，从缓存还原时 `toolchains/llvm/prebuilt/*/bin` 下的符号链接会指回已不存在的 `/opt/hostedtoolcache/...`，表现为 `aarch64-linux-android24-clang: line 4: .../bin/clang: No such file or directory`（链接器 exit 127）。该 action 还会修悬空链接并在编译前断言 `clang` 与两个目标 wrapper 都在
- 两个 `build-native*.mjs` 优先用带 API 号的 wrapper（`aarch64-linux-android24-clang`），缺失时退回 `clang --target=aarch64-linux-android24`；NDK r27+ 已移除这批 wrapper，升级 NDK 不用改脚本
- `customize.sh` 在包内无候选时也会调用它（`MODDIR=$MODPATH QSCD_NO_RESTART=1`）：装的是 `modules_update` 里的副本、服务还没起来，此时重启只会误杀上一版进程，所以用 `QSCD_NO_RESTART` 跳过。下载结果只影响提示文案，不影响安装成败

## Web 构建

- **源码**：`webui/`（Vue 3 + TypeScript + Vant 按需样式；结构见上；样式 `src/styles/`）
- **Vant**：`unplugin-vue-components` + `VantResolver` 按需打组件与样式；Toast / Dialog 函数 API 的样式在 `webui/src/app/plugins/vant.ts` 手动引入
- **类型检查**：`npm run typecheck:web`
- **Lint / 格式化**：见上表；CI 工作流 `Lint` 全量门禁，`Build Web` 仍跑 `npm run lint` + typecheck
- **一键检查**：`npm run check`
- **产物**：`.build/webroot/`，并同步覆盖 `module/webroot/`
- **模块 zip 只打入产物**（`.build/webroot`）；JS/CSS 带 content hash，避免管理器 WebView 吃到旧缓存
- zip 由 Node 写出 Unix 权限（`.sh` / `update-binary` 为 0755），Windows 不再使用 `Compress-Archive`
- 旧版原生源码见 `archives/webroot-vanilla-202607/`，勿当构建输入

## 工作流职责

| 工作流           | 触发                              | 职责                                                                           |
| ---------------- | --------------------------------- | ------------------------------------------------------------------------------ |
| `Lint`           | push / PR                         | ESLint、Stylelint、Markdown、Shellcheck、typecheck、Prettier、Commitlint（PR） |
| `Build Web`      | `webui/**`、web 构建脚本、package | Vite 构建 Web，上传 Artifact，推送 `dist-web`                                  |
| `Build Docs`     | `docs/**`                         | 构建并部署 GitHub Pages                                                        |
| `Package Module` | `webui/**`、`module/**`、打包脚本 | 构建 Magisk zip 并上传 Artifact（不发 Release）；打包前 **CI 戳版本**（见下）  |
| `Release Module` | **手动触发** / 推送 `v*` 标签     | 构建 zip + 创建 GitHub Release                                                 |

各工作流互不串联，只按路径变更自行触发。

### Package Module 的 CI 戳版本

`Package Module` 在打包前会跑 `tooling/scripts/stamp-ci-module-version.py`，**只改工作区** `module/module.prop` 的 `version` / `versionCode`，随后打进 Artifact：

- **不**改 `update.json` / `docs/public/**`，**不** commit，因此文档站与 Magisk 在线更新不会误报
- 展示名形如 `2026.09.13.ci.42`（带 `.ci.`，不会被发版解析当成正式修订号）
- `versionCode` 落在「上一正式版」与「下一档正式下限 − 1」之间，保证：
  - 不同 CI 包之间通常可热更新（`run_number` 映射进号段）
  - **当天第一次正式发版 `…01` 一定能热更新盖过发版前的 CI**
  - 发版脚本 `resolve-release-version.py` 与正式公式 `yyyyMMdd*100+rev` **不变**

本地默认 `npm run package:module` **不**戳号。若要模拟 CI：

```bash
# 需提供 run 号；会改写工作区 module.prop，用完请还原
set GITHUB_RUN_NUMBER=1   # PowerShell: $env:GITHUB_RUN_NUMBER=1
npm run package:module:ci
# 或：node tooling/scripts/run-python.mjs tooling/scripts/stamp-ci-module-version.py --run 1 --dry-run
npm run test:stamp-ci     # 号段边界自检
```

注意：当天已发正式版后再装 CI，号段可能顶到「次日 `…00`」；若同日还要发 `.2` 且需盖过该 CI，请用更高修订号。

### 手动发版

1. 开发中把用户可见改动写在根目录 `changelog.md` → `## Unreleased`（详见 [`RELEASE.md`](./RELEASE.md)）
2. GitHub → Actions → **Release Module** → Run workflow
3. 填写日期：当天第一版 `20260717`；同一天第二版 `20260717.2`
4. 可选：预发布 / 草稿
5. 工作流会：提升 Unreleased → 日期版本号；文档站两份 changelog **不含 Unreleased**；Release 正文优先取版本节（否则回退 Unreleased）+ GitHub Full Changelog

| 输入           | `version`      | `versionCode` |
| -------------- | -------------- | ------------- |
| `20260717`     | `2026.07.17`   | `2026071701`  |
| `20260717.2`   | `2026.07.17.2` | `2026071702`  |
| `2026.07.17.3` | `2026.07.17.3` | `2026071703`  |

### version / versionCode 约定

Magisk / KernelSU 要求 **`versionCode` 为 ≤ 2147483647 的 int**。

| 字段          | 格式                               | 示例                          |
| ------------- | ---------------------------------- | ----------------------------- |
| `version`     | `yyyy.MM.dd`（同日第 N 版加 `.N`） | `2026.07.17` / `2026.07.17.2` |
| `versionCode` | `yyyyMMdd * 100 + 修订号`（1–99）  | `2026071701` / `2026071702`   |

修订号默认 `1`（展示不加后缀）；同日再发填 `.2`、`.3`… 即可被管理器识别为更新。

不要再使用 12 位 `yyyyMMddHHmm` 作为 `versionCode`（会超 int 上限，检查更新失效）。

也可本地打标签推送：

```bash
git tag v2026.07.17
git push origin v2026.07.17
# 同日第二版：
git tag v2026.07.17.2
git push origin v2026.07.17.2
```

## 发布包内容

**正式包** `QSC-Battery_v<version>.zip`：入口脚本 + `bin/lib/*` + 只读 `diagnose.sh` / `test_switch.sh` + 统一 CLI `qsc.sh`。

**调试包** `QSC-Battery_v<version>-debug.zip`：另含 `testing.sh`、`diag2.sh`，并带 `bin/.qsc_debug`。

```bash
npm run package:module         # 正式包
npm run package:module:debug   # 调试包（文件名带 -debug）
```

### bin 脚本职责

| 路径                      | 职责                               |
| ------------------------- | ---------------------------------- |
| `common.sh`               | 路径初始化并加载 `lib/*`           |
| `lib/util.sh`             | 安全读节点、温度换算               |
| `lib/keys.sh`             | 音量键选择（安装与 Action）        |
| `lib/battery_info.sh`     | 电池健康/容量/循环（Action/WebUI） |
| `lib/profile.sh`          | 本机 MCA 探测与 `device.profile`   |
| `lib/charge.sh`           | 停充/恢复写入与节点列表            |
| `lib/jsonc.sh`            | current.json 解析                  |
| `lib/current.sh`          | 电流控制（可选）                   |
| `lib/status.sh`           | 动态 module.prop 简介              |
| `lib/power_saver.sh`      | 自适应轮询间隔与事件等待           |
| `qscd`                    | 事件唤醒守护（按 ABI 装入）        |
| `qscd_fetch.sh`           | 守护的下载/切换/删除（WebUI 调用） |
| `qsc_switch.sh`           | 停充策略主循环                     |
| `list_switch.sh`          | 扫描本机节点生成列表               |
| `detect_device.sh`        | 触发 profile 探测                  |
| `diagnose.sh`             | 只读诊断（正式包）                 |
| `test_switch.sh`          | 停充开关实测（正式包）             |
| `testing.sh` / `diag2.sh` | 调试工具（仅 debug 包）            |
