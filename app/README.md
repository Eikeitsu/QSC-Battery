# QSC Battery Companion App

Kotlin + Jetpack Compose 伴侣应用。只负责配置/状态/更新；**不挂后台**，停充逻辑仍由 Magisk 模块执行。

**APP 可不安装 Magisk 模块单独使用**（主题、检查更新、下载模块 zip）。装上模块后才能读写停充配置。

## 功能

- 主题：MIUIX / Material（设置项对齐 SukiSU：UiMode / ColorMode / Monet / AMOLED / 调色板）
- Root 读写 `/data/adb/modules/QSC_Battery`（有模块时）
- 主页状态、模块软开关（`off_qsc`）
- 策略 / 日志 / 配置档 / 守护下载 / APP·模块更新

## 构建（仅 GitHub Actions 云编译）

**请勿依赖本地 Android SDK。** 推送 `app/` 或手动触发 [App](../.github/workflows/app.yml) 工作流即可：

1. Actions → **App** → 产出 `qsc-companion-apk`（含 `QSC-Battery.apk`）
2. **Package Module** 会尝试拉取该 artifact，嵌入 zip 的 `app/QSC-Battery.apk`
3. 刷入模块时 **音量键可选安装** APP（默认可跳过）

本地若只有 Node，可刷新更新清单（不编译）：

```bash
npm run package:app -- --skip-build
```

## 更新通道

| 目标 | URL |
|------|-----|
| 模块 | https://eikeitsu.github.io/QSC-Battery/update.json |
| APP | https://eikeitsu.github.io/QSC-Battery/app-update.json |

## 包名

`com.qsc.battery`（debug：`com.qsc.battery.debug`）· `minSdk 33`
