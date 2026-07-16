# 安装与升级

## 环境要求

- 已安装 **Magisk** 或 **KernelSU**
- 建议使用支持 WebUI 的模块管理器（如 KernelSU 管理器）

## 安装步骤

1. 从 [GitHub Releases](https://github.com/Eikeitsu/QuantitativeStopCharging_switch_magisk/releases) 下载最新 zip
2. 在模块管理器中刷入
3. 重启手机
4. 进入模块页，打开 WebUI 按需调整阈值（「显示」里可切换浅色 / 深色 / 跟随系统）

支持 Magisk / KernelSU 的模块在线更新：`module.prop` 已配置 `updateJson`，管理器会拉取仓库根目录的 `update.json`。

## 模块目录（设备上）

```text
/data/adb/modules/QuantitativeStopCharging_switch/
├── module.prop
├── service.sh
├── bin/                 # 核心逻辑
├── config/config.conf   # 用户配置
├── data/                # 日志与运行状态
└── webroot/             # WebUI（发布包内为压缩产物）
```

## 从旧版升级

安装时会自动检查旧版根目录文件并迁移：

- `config.conf` → `config/config.conf`
- 日志、开关状态 → `data/`
- 清理根目录遗留脚本

详情见安装后的 `data/migrate.log`。

## 卸载

在模块管理器中卸载即可。卸载脚本会尝试恢复充电状态。
