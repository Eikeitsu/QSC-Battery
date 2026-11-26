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
| 动态 | 运行日志 + 充电事件 + LSP；**导出 zip** 系统分享反馈                                          |
| 我的 | 主题、更新、配置档、排障（调试开关 / 导出日志）、LSPosed/XP 面板、磁贴说明、权限              |
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

- **作用**（事实总线；**不停充**）：
  1. **前台包名总线**：`qsc_xp_fg`（+ edge）；简介 / 游戏旁路 / App 停充共用。门禁与分级同前。包名列表以 Magisk 写出的 `qsc_xp_*_pkgs` 为准。无 XP / alive 过期 / 软关 / 异常 → dumpsys 回退
  2. **管理器边沿队列**：`qsc_xp_viewer`；有 XP 时主服务消费并刷简介（不启 worker）；无 XP 才 dumpsys 降级 worker
  3. **插拔事实**：始终写 `qsc_xp_plug`；参与 Magisk 插电旁证（否决粘 present）；qscd 可 `--wake-file`；仅武装时另写 `qsc_xp_wake`
  4. **亮灭屏 / Doze 事实**：始终写；Doze idle 拉长未插电睡眠，**active 立刻复评**；面板 want_* 只控武装 wake
  5. **广播边沿**（默认关）：开启后可 `--wake-file` 并 bump `conf_reload` 复评
- **通道**：`/data/system/`；`qsc_xp_off` 全关；`qsc_xp_alive` 含 `v=` 且需心跳（过期回退 dumpsys）；APP 面板有总线快照
- **停充**始终由 Magisk 模块负责；无 LSPosed 时充电控制完整可用
- 排查：开 LSP「详细日志」后 `adb logcat -s QscXp`；现场 `sh …/bin/xp_bus_check.sh`；Rust qscd 可 poll plug / viewer / screen / doze / bcast / fg_edge
- **验证清单（刷含 APP 的模块并重启后）**：① 面板总线快照有 alive；② 拔插看 plug；③ 亮灭屏看 screen；④ Action 音量下→上出诊断；⑤ 无 XP 机确认停充仍正常

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
