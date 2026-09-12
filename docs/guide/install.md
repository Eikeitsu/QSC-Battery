# 安装与升级

## 环境要求

- 已安装 **Magisk** 或 **KernelSU**（或兼容方案）
- 使用 WebUI 需支持模块 WebUI 的管理器（如 KernelSU / SukiSU / MMRL / WebUI-X）
- 伴侣 APP 需 Android 13+（`minSdk 33`），读写模块需 Root

## 选哪个包

每个版本通常发 **4 个模块 zip**，功能相同，差别在是否自带「事件唤醒守护」qscd：

| 包名                           | 自带守护 | 适合                                                  |
| ------------------------------ | -------- | ----------------------------------------------------- |
| `QSC-Battery_v<版本>.zip`      | 不带     | **主包，推荐**；可在 WebUI 一键下载；在线更新也用此版 |
| `QSC-Battery_v<版本>-full.zip` | Rust + C | 装完即用，安装自检自动挑一套                          |
| `QSC-Battery_v<版本>-rust.zip` | 仅 Rust  | 要阈值过滤 / 原生进程检测等                           |
| `QSC-Battery_v<版本>-c.zip`    | 仅 C     | 只要轻量事件唤醒                                      |

守护只提供 **arm64 / armv7**；其它架构可跳过，停充不受影响。Rust / C **只能二选一**。主包安装时可选联网下载；之后可在 WebUI 切换并自动替换。

Release 还可能附带 **伴侣 APK**（也可由模块 zip 内嵌，刷入时可选安装）。

## 安装步骤

1. 从 [GitHub Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载 zip
2. 在模块管理器中刷入
3. **音量上**确认安装（约 20 秒；音量下或超时取消）
4. 选择是否安装 **WebUI**（超时默认装）
5. 选择是否安装 **电流控制**（超时默认装；总开关仍默认关）
6. 选择是否安装 **伴侣 APK**（若包内有）
7. 若本包无守护：可选联网下载并选 Rust / C；失败不中断安装
8. **重启**
9. 用 WebUI / APP / `config.conf` 调整；见 [WebUI](/guide/webui)、[APP](/guide/app)

### Action 按钮

- **音量上**（或超时）：刷新状态
- **音量下**：已插电 → 快速测开关；未插电 → 诊断报告 `/sdcard/qsc_diagnose.txt`

完整测开关也可：`sh .../bin/qsc.sh test-switch` 或 `bin/test_switch.sh`（须插电）。

## 在线更新

`module.prop` 配置了 `updateJson`，管理器拉主包。升级会尽量保留已下载的守护。APP、守护有独立通道，见 [伴侣 APP](/guide/app)。

## 更新配置怎么处理

检测到已装 `QSC_Battery` 时：

- **音量上**：保留**核心配置**（停充/恢复电量、温控、兼容模式、持锁、通知、无线、App 停充、自定义开关、时段、`current.json` 等）
- 同时：**省电与主循环间隔**（`power_saver`、`loop_interval_*`、`switch_verify_sec` 等）使用**新版默认**，让本版待机优化生效
- **音量下**：全部使用包内默认配置
- **超时**：按「保留核心配置」处理

若你曾手动改过省电间隔又想继续用旧值，更新后可在 WebUI「进阶」里再改回去。

WebUI / 电流控制 / APK 是否安装每次都会再问。

## 从旧版模块升级

显示名 **充电控制**，id **`QSC_Battery`**。

若仍装有下列旧版，本版会**自动卸载**且**不迁移配置**：

| 显示名                 | 模块 id                           |
| ---------------------- | --------------------------------- |
| QSC定量停充            | `QuantitativeStopCharging`        |
| QSC定量停充_独立开关版 | `QuantitativeStopCharging_switch` |

请安装后重新设阈值。

## 热更新说明

支持免重启热更新（管理器 / APP 安装模块时）。失败会回退到需重启的标准更新。诊断与临时文件可能位于 `/data/adb/qsc/`（更新完成后清理）。细节见 WebUI 文档「热更新」小节。

## 卸载

在模块管理器卸载即可。软关闭不必卸载：WebUI / APP / `qsc.sh off` 写 `data/off_qsc`。
