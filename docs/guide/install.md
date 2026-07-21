# 安装与升级

## 环境要求

- 已安装 **Magisk** 或 **KernelSU**
- 建议使用支持 WebUI 的模块管理器（如 KernelSU 管理器）

## 安装步骤

1. 从 [GitHub Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载最新 zip
2. 在模块管理器中刷入
3. 按安装日志提示，在 20 秒内按音量上确认安装；音量下或确认超时会取消安装
4. 按音量键选择是否安装 WebUI；20 秒未选择时默认安装
5. 重启手机
6. 若已安装 WebUI，可进入模块页按需调整阈值（「更多 → 显示」可切换主题、莫奈取色、悬浮分页等）

支持 Magisk / KernelSU 的模块在线更新：`module.prop` 已配置 `updateJson`，管理器会拉取仓库根目录的 `update.json`。

WebUI 概览页示意：

![概览](/screenshots/webui-overview.png)

## 更新当前版本

检测到 `/data/adb/modules/QSC_Battery/config/config.conf` 时，安装脚本会询问如何处理配置：

- **音量上**：保留原有 `config.conf`
- **音量下**：使用安装包中的新版默认配置
- **20 秒未选择**：默认保留原有配置，避免静默覆盖

WebUI 是否安装会在每次刷入时单独询问。选择不安装后不会保留 `webroot/`，模块核心停充脚本仍可正常运行，可直接编辑 `config/config.conf`。

## 从旧版升级

当前模块 id 为 **`QSC_Battery`**（仓库名 **QSC-Battery**）。

若设备上仍装有旧版 **`QuantitativeStopCharging_switch`**，安装本版时会：

1. 在安装日志中提示检测到旧版
2. **自动卸载旧版模块**（有 `uninstall.sh` 则执行；没有则只删除目录，不写充电节点）
3. **不会迁移**旧版配置与日志；安装后请重启，并在 WebUI 重新设置阈值

## 模块目录（设备上）

```text
/data/adb/modules/QSC_Battery/
├── module.prop
├── service.sh
├── bin/                 # 核心逻辑
├── config/config.conf   # 用户配置
├── data/                # 日志与运行状态
└── webroot/             # 可选 WebUI（发布包内为压缩产物）
```

## 卸载

在模块管理器中卸载即可。卸载脚本会尝试恢复充电状态。
