# 充电控制 · 伴侣 APP

Kotlin + Jetpack Compose（**Charge** 设计系统 · 沉浸式状态产品）。只负责配置/状态/更新；**不挂后台保活**，停充逻辑由 Magisk 模块执行。

**可不安装模块单独使用**（主题、检查更新、下载模块）。装上模块并授予 Root 后才能读写停充配置。

可选 **LSPosed 增强**（现代 API 102）：系统侧供电事件补强（不写充电节点）；注入后写心跳到 `/data/local/tmp/qsc_xp_heartbeat`（及备用路径）供 APP 检测。排查：`adb logcat -s QscXp`。

## 功能

- Charge UI：状态舞台首页、策略常用/进阶分层、动态时间线、工具箱「我的」
- 颜色：浅色 / 深色 / 纯黑 / 动态取色、调色板
- Root 读写 `/data/adb/modules/QSC_Battery`（有模块时）
- 首页 / 策略 / 动态 / 我的 · 配置档 / 更新
- 首启权限引导（返回后自动刷新）、快捷设置磁贴、可选 XP 模块

## 构建（仅 GitHub Actions）

推送 `app/` 或手动触发 **App** 工作流产出 APK。模块 zip **内嵌** `apk/QSC-Battery.apk`（约 3MB）；刷模块时可选安装。打包前需先有 `release/QSC-Battery.apk` 或本地 `assembleRelease`。

Release 使用仓库内固定密钥 `app/keystore/qsc-release.jks`（见 `keystore.properties`），保证每次 CI 签名一致、可覆盖安装。从旧的 debug 签名包升级时需**先卸载一次**。

```bash
npm run package:app -- --skip-build   # 只刷新 app-update.json
```

## 更新（三套独立通道）

| 目标 | URL | 谁在查 | 单独发版时 |
|------|-----|--------|------------|
| 模块 zip | [update.json](https://eikeitsu.github.io/QSC-Battery/update.json) | Magisk / APP「模块」 | 只勾 zip 才改 |
| 守护二进制 | [qscd/manifest.json](https://eikeitsu.github.io/QSC-Battery/qscd/manifest.json) | WebUI 守护卡片 | 只勾 Rust/C 才改 |
| APP | [app-update.json](https://eikeitsu.github.io/QSC-Battery/app-update.json) | APP「自身」 | 只勾 APK 才改 |

单独发布 APK 或守护**不会**改 `update.json`，因此不会触发 Magisk 模块更新提示。

桌面显示名：**充电控制** · 包名 `com.qsc.battery` · `minSdk 33` · `compileSdk/targetSdk 37`
