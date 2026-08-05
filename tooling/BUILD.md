# 构建与发布说明

面向维护者。用户文档请看 [`docs/`](../docs/)。

## 仓库结构

```text
webui/                  # WebUI 源码（Vue 3 + Vite + Vant + TypeScript，样式 Sass）
  src/bridge/           # ksu 桥接、配置、应用列表
  src/stores/           # 电池状态 / 主题
  src/shared/           # 路径、默认值、预设、类型
  src/features/         # 应用选择器等功能模块
  src/pages/            # 概览 / 策略 / 日志 / 我的
  src/ui/               # 通用 UI 组件
  src/styles/           # tokens / base / transitions

module/                 # Magisk 模块本体（打包 zip 的根内容来源）
  webroot/              # WebUI 构建产物（由 npm run build:web 同步）
archives/
  webroot-vanilla-*/    # 旧版原生 HTML/JS WebUI 归档（不参与打包）
tooling/scripts/        # 构建脚本
docs/                   # VitePress 用户文档
.release / .build/      # 本地产物（不入库）
```

## 本地命令

```bash
npm install
npm run prepare           # 启用 husky（install 后一般会自动跑）
npm run dev:web           # Vite 开发预览 webui/
npm run build:web         # Vite 构建 → .build/webroot，并同步到 module/webroot
npm run package:module    # 打 Magisk zip（需先 build:web）
npm run build:module      # build:web + package:module
npm run check             # typecheck + 全量 lint + prettier check
npm run lint              # eslint + stylelint + markdownlint + shellcheck
npm run format            # prettier 写回
npm run dev:docs          # 文档预览
npm run build:docs        # 构建文档站点
```

### Lint 矩阵

| 命令               | 覆盖                                                      |
| ------------------ | --------------------------------------------------------- |
| `lint:js`          | `webui` Vue/TS、`tooling` 脚本、VitePress 配置            |
| `lint:style`       | `webui` SCSS / Vue `<style>`（Stylelint）                 |
| `lint:md`          | Markdown（markdownlint-cli2）                             |
| `lint:shell`       | `module/**/*.sh`（shellcheck；本机未安装则跳过，CI 强制） |
| husky `commit-msg` | Conventional Commits（commitlint）                        |
| husky `pre-commit` | lint-staged（改动文件的 eslint/stylelint/prettier/md）    |

**不需要** pnpm monorepo：本仓是「Magisk 模块 + 单一 WebUI + 文档」单体，只有一个 `package.json` 与一套依赖；拆 workspace 会增加 CI/路径复杂度而几乎没有包复用收益。继续用 npm 即可。

## Web 构建

- **源码**：`webui/`（Vue 3 + TypeScript + Vant；结构见上；样式 `src/styles/`）
- **类型检查**：`npm run typecheck:web`
- **Lint / 格式化**：见上表；CI 工作流 `Lint` 全量门禁，`Build Web` 仍跑 `npm run lint` + typecheck
- **一键检查**：`npm run check`
- **产物**：`.build/webroot/`，并同步覆盖 `module/webroot/`
- **模块 zip 只打入产物**（`.build/webroot`）
- 旧版原生源码见 `archives/webroot-vanilla-202607/`，勿当构建输入

## 工作流职责

| 工作流           | 触发                              | 职责                                                                           |
| ---------------- | --------------------------------- | ------------------------------------------------------------------------------ |
| `Lint`           | push / PR                         | ESLint、Stylelint、Markdown、Shellcheck、typecheck、Prettier、Commitlint（PR） |
| `Build Web`      | `webui/**`、web 构建脚本、package | Vite 构建 Web，上传 Artifact，推送 `dist-web`                                  |
| `Build Docs`     | `docs/**`                         | 构建并部署 GitHub Pages                                                        |
| `Package Module` | `module/**`、打包脚本             | 仅构建 Magisk zip 并上传 Artifact（不发 Release）                              |
| `Release Module` | **手动触发** / 推送 `v*` 标签     | 构建 zip + 创建 GitHub Release                                                 |

各工作流互不串联，只按路径变更自行触发。

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

**正式包** `QSC-Battery_v<version>.zip`：入口脚本 + `bin/lib/*` + 只读 `diagnose.sh` / `test_switch.sh`。

**调试包** `QSC-Battery_v<version>-debug.zip`：另含 `testing.sh`、`diag2.sh`，并带 `bin/.qsc_debug`。

```bash
npm run package:module         # 正式包
npm run package:module:debug   # 调试包（文件名带 -debug）
```

### bin 脚本职责

| 路径                      | 职责                             |
| ------------------------- | -------------------------------- |
| `common.sh`               | 路径初始化并加载 `lib/*`         |
| `lib/util.sh`             | 安全读节点、温度换算             |
| `lib/keys.sh`             | 音量键选择                       |
| `lib/profile.sh`          | 本机 MCA 探测与 `device.profile` |
| `lib/charge.sh`           | 停充/恢复写入与节点列表          |
| `lib/jsonc.sh`            | current.jsonc 解析               |
| `lib/current.sh`          | 电流控制（可选）                 |
| `lib/status.sh`           | 动态 module.prop 简介            |
| `qsc_switch.sh`           | 停充策略主循环                   |
| `list_switch.sh`          | 扫描本机节点生成列表             |
| `detect_device.sh`        | 触发 profile 探测                |
| `diagnose.sh`             | 只读诊断（正式包）               |
| `test_switch.sh`          | 停充开关实测（正式包）           |
| `testing.sh` / `diag2.sh` | 调试工具（仅 debug 包）          |
