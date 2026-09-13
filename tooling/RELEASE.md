# 发版与更新日志（给维护者 / AI）

> 编码改功能或修 bug 时：**先写 `changelog.md` 的 `## Unreleased`**，再改代码。  
> 用户可见的文档站日志在发版时由工作流从 `changelog.md` 同步；开发中也可手动同步以便预览文档站。

## 日志写哪里

| 文件                       | 用途                                                       |
| -------------------------- | ---------------------------------------------------------- |
| 仓库根目录 `changelog.md`  | **唯一手写源**。开发中把条目写在 `## Unreleased` 下        |
| `docs/guide/changelog.md`  | 文档站「更新日志」页（发版工作流同步；开发预览可手动复制） |
| `docs/public/changelog.md` | Pages / `updateJson` 指向的 changelog（同上）              |

### Unreleased 写法

```markdown
## Unreleased

- 用一两句说清用户能感知的变化（修了什么 / 新增什么）
- 一条一个要点；重大版本可用小标题分组
```

- 发版前保持 `## Unreleased` 在文件最上方（标题 `# 更新日志` 之后）。
- 版本号格式：`## 2026.07.25` 或 `## 2026.07.25.2`（由发版工作流写入）。

## 发版时工作流做什么

Actions → **Release Module**（或推送 `v*` tag）：

发版对话框可勾选 4 项（默认全选）：

| 勾选      | GitHub Release 资产                 | 会改哪条更新通道                                          |
| --------- | ----------------------------------- | --------------------------------------------------------- |
| 模块 zip  | 5 个变体 zip（`update.json` → `-full`） | `update.json` + `module.prop`（Magisk / APP「模块更新」） |
| Rust 守护 | `qscd-rust-arm64` / `qscd-rust-arm` | `qscd/manifest.json`（WebUI 守护卡片）                    |
| C 守护    | `qscd-c-arm64` / `qscd-c-arm`       | 同上                                                      |
| 伴侣 APK  | `QSC-Battery_v*.apk`                | `app-update.json`（APP 自身更新）                         |

### 单独发版时「模块检测更新」怎么处理

三套通道彼此独立，**只改勾选项对应的清单**，不会互相误报：

| 场景              | Magisk / APP 模块更新              | WebUI 守护更新                | APP 自身更新                      |
| ----------------- | ---------------------------------- | ----------------------------- | --------------------------------- |
| 只勾 zip          | 有（`update.json` 新 versionCode） | 否                            | 否                                |
| 只勾 Rust 和/或 C | **否**（不碰 `update.json`）       | 有（`manifest.version` bump） | 否                                |
| 只勾 APK          | **否**                             | 否                            | 有（需先 bump APP `versionCode`） |
| 全选              | 有                                 | 有                            | 有                                |

要点：

1. **模块更新只认 `update.json`**。单独发二进制 / APK 时 post 脚本故意不改它，Magisk 管理器和 APP「检查模块更新」不会被骗。
2. **守护更新只认 `qscd/manifest.json`**。只发 Rust 时保留 Pages 上旧的 C 文件；只发 C 同理。任一套发布都会写入本次 `version`，WebUI 可检出新守护。
3. **APP 更新只认 `app-update.json`**。只发 APK 前请先提高 `app/app/build.gradle.kts` 的 `versionCode` / `versionName`。
4. 同日只修守护或 APK：版本可用 `20260717.2` 这类后缀；changelog 仍会 promote，但模块 `update.json` 可保持旧版。

工作流步骤：

1. 打包模块 zip + 编译守护 / APK，按勾选创建 GitHub Release（正文优先取当前版本节；没有则回退 Unreleased）
2. `promote-changelog.py <version>`：非空 `Unreleased` → 当前日期版本号，并留下空 stub
3. `promote-changelog.py --export-docs`：文档站两份 changelog **去掉 Unreleased**
4. 按勾选更新 `update.json` / `qscd/manifest` / `app-update.json` 等并推送主分支；因 `GITHUB_TOKEN` 推送不会连锁触发其它 Actions，脚本会再 `gh workflow run build-docs.yml`

工作流拆为 `build` → `publish` → `post` 三阶段；版本解析见 `resolve-release-version.py`，回写见 `post-release-update.sh`。

## 本地命令（可选）

```bash
python3 tooling/scripts/promote-changelog.py 2026.07.25 changelog.md

python3 tooling/scripts/promote-changelog.py --export-docs changelog.md \
  docs/guide/changelog.md docs/public/changelog.md
```

## AI / 协作者检查清单

1. 有用户可见改动 → `changelog.md` → `## Unreleased` 追加 bullet
2. 不要把 Unreleased 写进 `docs/**/changelog.md`
3. 不要删空的 `## Unreleased` stub
4. 发版用工作流，勿漏同步文档站两份日志
5. 只发 APK 时 bump APP `versionCode`；只发守护时不必 bump 模块 `update.json`

相关脚本：`promote-changelog.py`、`prepare-release-notes.py`、`resolve-release-version.py`、`post-release-update.sh`。  
构建细节见 [`BUILD.md`](./BUILD.md)。
