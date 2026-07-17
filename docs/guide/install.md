# 安装与升级

## 环境要求

- 已安装 **Magisk** 或 **KernelSU**
- 建议使用支持 WebUI 的模块管理器（如 KernelSU 管理器）

## 安装步骤

1. 从 [GitHub Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载最新 zip
2. 在模块管理器中刷入
3. 重启手机
4. 进入模块页，打开 WebUI 按需调整阈值（「显示」里可切换浅色 / 深色 / 跟随系统）

支持 Magisk / KernelSU 的模块在线更新：`module.prop` 已配置 `updateJson`，管理器会拉取仓库根目录的 `update.json`。

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
└── webroot/             # WebUI（发布包内为压缩产物）
```

## 卸载

在模块管理器中卸载即可。卸载脚本会尝试恢复充电状态。
