<div align="center">

# 充电控制 · 伴侣 APP

Kotlin + Jetpack Compose。配置 / 状态 / 更新 / 主题；**不挂后台保活**。停充由 Magisk 模块执行。

[用户文档](https://eikeitsu.github.io/QSC-Battery/guide/app.html) · [Releases](https://github.com/Eikeitsu/QSC-Battery/releases) · [主仓库](../../README.md)

<br />

[![Release](https://img.shields.io/github/v/release/Eikeitsu/QSC-Battery?style=for-the-badge&label=Release)](https://github.com/Eikeitsu/QSC-Battery/releases)
[![Android](https://img.shields.io/badge/Android-8%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://eikeitsu.github.io/QSC-Battery/guide/app.html)
[![minSdk](https://img.shields.io/badge/minSdk-26-blue?style=for-the-badge)](./build.gradle.kts)
[![Compose](https://img.shields.io/badge/Jetpack-Compose-4285F4?style=for-the-badge&logo=jetpackcompose&logoColor=white)](https://developer.android.com/jetpack/compose)
[![Package](https://img.shields.io/badge/package-com.qsc.battery-informational?style=for-the-badge)](./src/main/AndroidManifest.xml)

<br />

<img src="https://skillicons.dev/icons?i=kotlin,androidstudio,gradle,githubactions" alt="Tech stack" />

</div>

`minSdk 26`（Android 8+）· `compileSdk 37` / `targetSdk 35` · JDK 17

## 功能摘要

- 首页 / 策略 / 动态 / 我的；Root 读写模块
- 主题：浅/深/AMOLED/动态取色、调色板
- 动态桌面图标（约 10% 档 + 充电黄闪）；快捷设置磁贴
- 可选 LSPosed：系统框架插拔边沿唤醒（qscd 降级时）；配置/存活标记检测
- 首启引导、配置档、检查模块/自身更新

## 技术栈

按 `gradle/libs.versions.toml` / `build.gradle.kts`：

| 区域          | 技术                                                                  |
| ------------- | --------------------------------------------------------------------- |
| 语言          | Kotlin 2.4 · JVM 17                                                   |
| UI            | Jetpack Compose（BOM）· Material 3 · Material Icons Extended          |
| 导航 / 架构   | Navigation Compose · Activity Compose · Lifecycle / ViewModel Compose |
| 异步 / 序列化 | Kotlin Coroutines · kotlinx.serialization JSON                        |
| 本地存储      | DataStore Preferences                                                 |
| Root          | libsu（`core` + `io`）                                                |
| 网络          | OkHttp（模块 / APP / 守护更新检查）                                   |
| 主题          | MaterialKolor（动态取色）                                             |
| Xposed        | libxposed API（compileOnly）+ libxposed Service                       |
| 构建          | AGP 9 · Gradle · Compose / Serialization 插件                         |
| 质量          | Spotless + ktlint · R8 / ProGuard（release minify）                   |
| CI            | GitHub Actions（**App** 打 APK；**Lint** 跑 Spotless）                |

图标来自 [Skill Icons](https://skillicons.dev)；徽章来自 [Shields.io](https://shields.io)。

## 构建

推送 `apps/android/` 或手动触发 **App** 工作流。模块 zip 可内嵌 `apk/QSC-Battery.apk`。Release 使用仓库固定密钥，保证可覆盖安装。

```bash
cd apps/android
./gradlew spotlessApply
./gradlew spotlessCheck

# 仓库根目录等价：
npm run format:kotlin
npm run lint:kotlin
```

Kotlin 缩进为 **4 空格**（本目录 `.editorconfig`），Spotless `ktlint()` 会读取。CI 仅在 **Lint** 的 Kotlin job 跑 `spotlessCheck`；**App** 工作流只负责构建 APK。

## 更新通道

| 目标 | URL                                                         |
| ---- | ----------------------------------------------------------- |
| 模块 | <https://eikeitsu.github.io/QSC-Battery/update.json>        |
| 守护 | <https://eikeitsu.github.io/QSC-Battery/qscd/manifest.json> |
| APP  | <https://eikeitsu.github.io/QSC-Battery/app-update.json>    |

单独发 APK/守护不会改模块 `update.json`。
