# 伴侣 APP

包名 `com.qsc.battery` · 桌面名 **充电控制** · Kotlin + Jetpack Compose · Android 8+（`minSdk 26`）。

只负责配置、状态、更新与主题；**不挂后台保活**。停充逻辑始终由 Magisk 模块执行。

**可不装模块单独使用**（主题、检查更新、下载模块）。装上模块并授权 Root 后才能读写停充配置。

## 功能

| 区域 | 内容                                                                                          |
| ---- | --------------------------------------------------------------------------------------------- |
| 引导 | Root / 通知 / 安装包 / XP 检测                                                                |
| 首页 | 状态舞台、软开关、策略入口                                                                    |
| 策略 | 常用停充/温度；进阶含 **省电策略**（档位/息屏/夜间）、持锁、无线、通知、App、历史、电流、守护 |
| 动态 | 运行日志 + 充电事件 + LSP（本模块 XP）                                                        |
| 我的 | 主题、更新、配置档、LSPosed/XP 面板、磁贴说明、权限                                           |
| 磁贴 | 快捷设置切换 `module_off`（需 Root+模块）                                                     |

### 主题与图标

- 颜色模式：跟随系统 / 浅 / 深 / 纯黑 AMOLED / 动态取色
- 调色板与种子色
- **动态桌面图标**（默认关）：电量约 10% 一档；充电时闪电为黄色；默认/环形两套风格
- 仅打开 APP 或插拔电等稀疏时机刷新（不监听每秒 `BATTERY_CHANGED`）

### LSPosed（可选）

作用域勾选 **系统框架**（包名 `system`；仅勾「Android系统」`android` 不够）。APP「我的 → LSPosed / XP」可一键 `requestScope("system")`。

三层状态（不必为①②重启；③注入需重启）：

1. **服务已连接**：`XposedService` binder（官方 libxposed service，打开 APP 即可）
2. **作用域已含 system**：`getScope()` / 一键请求
3. **框架已注入**：`/data/system/qsc_xp_alive` 或 `runningTargets` 含 system_server

- **作用**：
  1. **前台包名总线**：`qsc_xp_fg`（+ edge）；简介 / 游戏旁路 / App 停充共用。**门禁**：三者全关时 XP 不写盘。**分级**：仅简介→管理器；游戏/停充→各自包名列表。管理器 **3s 稳定 + 90s 离开超时**；列表约 **1s 进 / 30s 离**（游戏另认进程）。普通 App fg 落盘 **800ms**。无 XP、软关或策略空闲/异常时回退 dumpsys，边沿恢复后再切回
  2. **管理器边沿**：`qsc_xp_viewer` enter/leave（经稳定 + 离开超时）
  3. **插拔边沿**：仅 qscd 不可用且已武装时写 `qsc_xp_wake`
  4. **辅助边沿（默认关）**：`want_screen` / `want_doze` / `want_bcast` → 分别写 `qsc_xp_screen` / `qsc_xp_doze` / `qsc_xp_bcast`；息屏策略优先读 screen；武装时亦可打断 sleep。广播动作列表见 `qsc_xp_bcast_actions`（空则用内置 SCREEN/IDLE/插拔）
- **通道**：`/data/system/`；`qsc_xp_off` 全关；`qsc_xp_no_wake` 仅关插拔唤醒；`qsc_xp_no_viewer` 关前台总线
- **停充**始终由 Magisk 模块负责
- 排查：动态页 LSP Tab，或 `adb logcat -s QscXp`；成功可见 `ok fg` / `ok viewer enter|leave` / `ok assist`

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

推送 `apps/android/` 或手动触发 GitHub Actions **App** 工作流。详见仓库 [`apps/android/README.md`](https://github.com/Eikeitsu/QSC-Battery/blob/main/apps/android/README.md)。
