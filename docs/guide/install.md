# 安装与升级

## 环境要求

- 已安装 **Magisk** 或 **KernelSU**
- 建议使用支持 WebUI 的模块管理器（如 KernelSU 管理器）

## 安装步骤

1. 从 [GitHub Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载最新 zip
2. 在模块管理器中刷入
3. 按安装日志提示，在 20 秒内按音量上确认安装；音量下或确认超时会取消安装
4. 按音量键选择是否安装 **WebUI**；20 秒未选择时默认安装
5. 按音量键选择是否安装 **电流控制** 组件；20 秒未选择时默认安装（装入后总开关仍默认关闭）
6. 重启手机
7. 若已安装 WebUI，可进入模块页按需调整阈值（「更多 → 显示」可切换主题、莫奈取色、悬浮分页等）

支持 Magisk / KernelSU 的模块在线更新：`module.prop` 已配置 `updateJson`，管理器会拉取仓库根目录的 `update.json`。

WebUI 概览页示意：

![概览](/screenshots/webui-overview.png)

## 更新当前版本

检测到已安装的 `QSC_Battery` 时，安装脚本会询问如何处理配置：

- **音量上**：保留原有 `config.conf`；若同时安装电流控制且存在旧 `current.json`，也会一并保留
- **音量下**：使用安装包中的新版默认配置
- **20 秒未选择**：默认保留原有配置，避免静默覆盖

WebUI、电流控制是否安装会在每次刷入时**分别询问**。

- 选择不安装 WebUI：不保留 `webroot/`，可直接编辑配置文件
- 选择不安装电流控制：删除 `bin/lib/current.sh` 与 `config/current.json`，不写入相关功能

## 从旧版升级

当前模块显示名为 **充电控制**，id 为 **`QSC_Battery`**（仓库名 **QSC-Battery**）。

若设备上仍装有以下旧版，安装本版时会自动卸载（**不迁移配置**）：

| 显示名                 | 模块 id                           |
| ---------------------- | --------------------------------- |
| QSC定量停充            | `QuantitativeStopCharging`        |
| QSC定量停充_独立开关版 | `QuantitativeStopCharging_switch` |

流程：

1. 安装日志提示检测到旧版（输出上述显示名）
2. **自动卸载旧版**（有 `uninstall.sh` 则执行；没有则只删除目录，不写充电节点）
3. 请重启，并在 WebUI 重新设置阈值

## 模块目录（设备上）

```text
/data/adb/modules/QSC_Battery/
├── module.prop
├── service.sh
├── bin/                      # 核心逻辑（含 bin/lib/）
├── config/
│   ├── config.conf           # 停充配置
│   └── current.json          # 电流控制（可选）
├── data/                     # 日志与运行状态
└── webroot/                  # 可选 WebUI
```

## 卸载

在模块管理器中卸载即可。卸载脚本会尝试恢复充电状态。
