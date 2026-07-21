# 构建与发布说明

面向维护者。用户文档请看 [`docs/`](../docs/)。

## 仓库结构

```text
module/                 # Magisk 模块本体（打包 zip 的根内容来源）
  webroot/              # WebUI 可读源码
tooling/scripts/        # 构建脚本
docs/                   # VitePress 用户文档
.release / .build/      # 本地产物（不入库）
```

## 本地命令

```bash
npm install
npm run dev:web          # 预览 module/webroot 源码
npm run build:web        # 压缩 HTML/CSS/JS → .build/webroot
npm run package:module   # 打 Magisk zip（需先 build:web）
npm run build:module     # build:web + package:module
npm run dev:docs         # 文档预览
npm run build:docs       # 构建文档站点
```

## Web 构建

- **源码**：`module/webroot/`（保持可读，便于开发）
- **产物**：`.build/webroot/`（HTML/CSS/JS 压缩；保留全局名保证 WebUI 可运行）
- **模块 zip 只打入产物**，不打入可读源码

## 工作流职责

| 工作流           | 触发                              | 职责                                              |
| ---------------- | --------------------------------- | ------------------------------------------------- |
| `Build Web`      | `module/webroot/**`、web 构建脚本 | 压缩混淆 Web，上传 Artifact，推送 `dist-web`      |
| `Build Docs`     | `docs/**`                         | 构建并部署 GitHub Pages                           |
| `Package Module` | `module/**`、打包脚本             | 仅构建 Magisk zip 并上传 Artifact（不发 Release） |
| `Release Module` | **手动触发** / 推送 `v*` 标签     | 构建 zip + 创建 GitHub Release                    |

各工作流互不串联，只按路径变更自行触发。

### 手动发版

1. GitHub → Actions → **Release Module** → Run workflow
2. 填写日期：当天第一版 `20260717`；同一天第二版 `20260717.2`
3. 可选：预发布 / 草稿
4. 运行后自动规范版本并发布

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

仅运行时必要文件：`module.prop`、入口脚本、`META-INF`、`bin` 核心脚本、`config`、空 `data`、压缩后的 `webroot`。

```bash
npm run package:module:debug   # 额外带上 diagnose/testing/diag2
```
