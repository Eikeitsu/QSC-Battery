# 充电控制 · 伴侣 APP

Kotlin + Jetpack Compose。配置 / 状态 / 更新 / 主题；**不挂后台保活**。停充由 Magisk 模块执行。

- 用户文档：[伴侣 APP](https://eikeitsu.github.io/QSC-Battery/guide/app.html)
- 包名 `com.qsc.battery` · `minSdk 33` · `compileSdk/targetSdk 37`

## 功能摘要

- 首页 / 策略 / 动态 / 我的；Root 读写模块
- 主题：浅/深/AMOLED/动态取色、调色板
- 动态桌面图标（约 20% 档 + 充电黄闪）；快捷设置磁贴
- 可选 LSPosed API 102 供电事件补强（不写充电节点）
- 首启引导、配置档、检查模块/自身更新

## 构建

推送 `app/` 或手动触发 **App** 工作流。模块 zip 可内嵌 `apk/QSC-Battery.apk`。Release 使用仓库固定密钥，保证可覆盖安装。

```bash
npm run package:app -- --skip-build   # 只刷新 app-update.json
```

## 更新通道

| 目标 | URL |
| ---- | --- |
| 模块 | <https://eikeitsu.github.io/QSC-Battery/update.json> |
| 守护 | <https://eikeitsu.github.io/QSC-Battery/qscd/manifest.json> |
| APP | <https://eikeitsu.github.io/QSC-Battery/app-update.json> |

单独发 APK/守护不会改模块 `update.json`。
