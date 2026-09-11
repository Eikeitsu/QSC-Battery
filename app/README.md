# 充电控制 · 伴侣 APP

Kotlin + Jetpack Compose（**Volt** 沉浸式界面）。只负责配置/状态/更新；**不挂后台保活**，停充逻辑由 Magisk 模块执行。

**可不安装模块单独使用**（主题、检查更新、下载模块）。装上模块并授予 Root 后才能读写停充配置。

可选 **LSPosed 增强**（现代 API 102）：系统侧供电事件补强（不写充电节点）；注入后写心跳文件供 APP 检测。

## 功能

- Volt UI：沉浸状态栏/导航栏、电量英雄区、分组列表
- 颜色：浅色 / 深色 / 纯黑 / 动态取色、调色板
- Root 读写 `/data/adb/modules/QSC_Battery`（有模块时）
- 概览 / 策略 / 日志 / 我的 · 配置档 / 守护 / 更新
- 首启权限引导（返回后自动刷新）、快捷设置磁贴、可选 XP 模块

## 构建（仅 GitHub Actions）

推送 `app/` 或手动触发 **App** 工作流产出 APK。模块 zip **不内嵌** APK；刷模块时可选在线下载安装。

```bash
npm run package:app -- --skip-build   # 只刷新 app-update.json
```

## 更新

| 目标 | URL |
|------|-----|
| 模块 | [update.json](https://eikeitsu.github.io/QSC-Battery/update.json) |
| APP | [app-update.json](https://eikeitsu.github.io/QSC-Battery/app-update.json) |

桌面显示名：**充电控制** · 包名 `com.qsc.battery` · `minSdk 33` · `compileSdk/targetSdk 37`
