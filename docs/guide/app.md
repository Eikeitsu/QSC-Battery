# 伴侣 APP

包名 `com.qsc.battery` · 桌面名 **充电控制** · Kotlin + Jetpack Compose。

只负责配置、状态、更新与主题；**不挂后台保活**。停充逻辑始终由 Magisk 模块执行。

**可不装模块单独使用**（主题、检查更新、下载模块）。装上模块并授权 Root 后才能读写停充配置。

## 功能

| 区域 | 内容                                                                   |
| ---- | ---------------------------------------------------------------------- |
| 引导 | Root / 通知 / 安装包 / XP 检测                                         |
| 首页 | 状态舞台、软开关、策略入口                                             |
| 策略 | 常用停充/温度；进阶：持锁、无线、通知、App、省电、历史、电流部分、守护 |
| 动态 | 运行日志 + 充电事件                                                    |
| 我的 | 主题、更新、配置档、XP、磁贴说明、权限                                 |
| 磁贴 | 快捷设置切换 `off_qsc`（需 Root+模块）                                 |

### 主题与图标

- 颜色模式：跟随系统 / 浅 / 深 / 纯黑 AMOLED / 动态取色
- 调色板与种子色
- **动态桌面图标**：电量约 20% 一档；充电时闪电为黄色；默认/环形两套风格
- 仅打开 APP 或插拔电等稀疏时机刷新（不监听每秒 `BATTERY_CHANGED`）

### LSPosed（可选）

现代 API **102**，作用域建议勾选系统框架 `android`。

- Hook 供电相关路径，写唤醒提示供模块缩短等待（**不写充电节点**）
- APP 内可关「XP 供电事件补强」；也可放 `/data/local/tmp/qsc_xp_power_events_off`
- 排查：`adb logcat -s QscXp`

## 安装

1. Release 中的 APK，或刷模块时选择安装内嵌 APK
2. 固定 release 签名；从旧 debug 包升级需先卸载一次
3. 授予 Root（读写模块）与通知权限（可选）

## 更新通道（三套独立）

| 目标     | 清单                                                                            | 谁在查               |
| -------- | ------------------------------------------------------------------------------- | -------------------- |
| 模块 zip | [update.json](https://eikeitsu.github.io/QSC-Battery/update.json)               | Magisk / APP「模块」 |
| qscd     | [qscd/manifest.json](https://eikeitsu.github.io/QSC-Battery/qscd/manifest.json) | WebUI 守护卡片       |
| APP      | [app-update.json](https://eikeitsu.github.io/QSC-Battery/app-update.json)       | APP「自身」          |

单独发 APK 或守护**不会**改模块 `update.json`，避免误提示 Magisk 更新。

## 构建（维护者）

推送 `app/` 或手动触发 GitHub Actions **App** 工作流。详见仓库 [`app/README.md`](https://github.com/Eikeitsu/QSC-Battery/blob/main/app/README.md)。
