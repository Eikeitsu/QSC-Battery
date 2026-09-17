# 充电控制 · 伴侣 APP

Kotlin + Jetpack Compose。配置 / 状态 / 更新 / 主题；**不挂后台保活**。停充由 Magisk 模块执行。

- 用户文档：[伴侣 APP](https://eikeitsu.github.io/QSC-Battery/guide/app.html)
- 包名 `com.qsc.battery` · `minSdk 26`（Android 8+）· `compileSdk 37` / `targetSdk 35`

## 功能摘要

- 首页 / 策略 / 动态 / 我的；Root 读写模块
- 主题：浅/深/AMOLED/动态取色、调色板
- 动态桌面图标（约 10% 档 + 充电黄闪）；快捷设置磁贴
- 可选 LSPosed：系统框架插拔边沿唤醒（qscd 降级时）；配置/存活标记检测
- 首启引导、配置档、检查模块/自身更新

## 构建

推送 `apps/android/` 或手动触发 **App** 工作流。模块 zip 可内嵌 `apk/QSC-Battery.apk`。Release 使用仓库固定密钥，保证可覆盖安装。

```bash
# 本地格式 / 检查（Spotless + ktlint；需 JDK）
cd apps/android
./gradlew spotlessApply   # 写回
./gradlew spotlessCheck   # 与 Lint 工作流 kotlin job 同款

npm run format:kotlin     # 仓库根目录，同上 spotlessApply
npm run lint:kotlin       # 仓库根目录，同上 spotlessCheck
```

Kotlin 缩进为 **4 空格**，由本目录 `apps/android/.editorconfig` 指定（覆盖仓库根 `.editorconfig` 的 2 空格），Spotless `ktlint()` 会读取该文件。CI 仅在 **Lint** 工作流的 `Kotlin (Spotless / ktlint)` job 跑 `spotlessCheck`；**App** 工作流只负责构建 APK。

## 更新通道

| 目标 | URL |
| ---- | --- |
| 模块 | <https://eikeitsu.github.io/QSC-Battery/update.json> |
| 守护 | <https://eikeitsu.github.io/QSC-Battery/qscd/manifest.json> |
| APP | <https://eikeitsu.github.io/QSC-Battery/app-update.json> |

单独发 APK/守护不会改模块 `update.json`。
