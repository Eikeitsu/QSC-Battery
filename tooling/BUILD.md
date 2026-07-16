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
- **产物**：`.build/webroot/`（HTML/CSS/JS 均压缩；JS 额外混淆）
- **模块 zip 只打入产物**，不打入可读源码

## 工作流职责

| 工作流 | 触发路径 | 职责 |
|--------|----------|------|
| `Build Web` | `module/webroot/**`、web 构建脚本 | 压缩混淆 Web，上传 Artifact，推送 `dist-web` |
| `Build Docs` | `docs/**` | 构建并部署 GitHub Pages |
| `Package Module` | `module/**`、打包相关脚本、`v*` 标签 | 构建 Web + 打精简 Magisk zip；tag 时发 Release |

各工作流互不串联，只按路径变更自行触发。

## 发布包内容

仅运行时必要文件：`module.prop`、入口脚本、`META-INF`、`bin` 核心脚本、`config`、空 `data`、压缩后的 `webroot`。

```bash
npm run package:module:debug   # 额外带上 diagnose/testing/diag2
```
