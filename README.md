# QSC 充电控制（原定量停充 WebUI 版）

基于 **top大佬** 的 QSC 定量停充，由 **许小墨** 维护。模块显示名：**充电控制**（id 为 `QSC_Battery`）。

电量 / 温度停充与恢复，并可选 **电流控制**（模拟旁路、慢充、温度阶梯限流、游戏限流；通用 sysfs，默认关闭）。

- **本仓库**：[Eikeitsu/QSC-Battery](https://github.com/Eikeitsu/QSC-Battery)
- **在线文档**：[eikeitsu.github.io/QSC-Battery](https://eikeitsu.github.io/QSC-Battery/)
- **QSC 定量停充**：[410154425/QuantitativeStopCharging_switch_magisk](https://github.com/410154425/QuantitativeStopCharging_switch_magisk)

## WebUI 预览

|                        概览                         |                       策略                        |
| :-------------------------------------------------: | :-----------------------------------------------: |
| ![概览](docs/public/screenshots/webui-overview.png) | ![策略](docs/public/screenshots/webui-config.png) |

|                      日志                      |                      我的                       |
| :--------------------------------------------: | :---------------------------------------------: |
| ![日志](docs/public/screenshots/webui-log.png) | ![我的](docs/public/screenshots/webui-more.png) |

## 功能概览

- 电量 / 温度阈值停充与恢复；多条件同时触发时，全部达到恢复条件后才重新充电
- 充满再停、自动拔插；**兼容模式**可跳过电流控制以便与其它限流模块共存
- Action：音量上刷新状态，音量下生成只读诊断；停充开关实测请插电后执行 `bin/test_switch.sh`
- **电流控制（安装时可选，默认关）**：独立配置 `config/current.json`；模拟旁路 / 慢充 / 默认限流 / 电流温控 / 游戏限流
- 可选 WebUI：状态、配置、日志；主题 / 莫奈取色 / 悬浮底栏 / 卡片紧凑等显示选项
- 更新时可用音量键选择保留原配置或恢复默认配置
- 模块 id：`QSC_Battery`；支持 `updateJson` 在线更新

## 快速开始（用户）

1. 从 [Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载 zip
2. 刷入模块，按音量键确认安装，并选择是否安装 WebUI / 电流控制
3. 更新安装时选择保留原配置或使用新版默认配置
4. 重启后通过 WebUI 或 `config/config.conf`（电流控制为 `config/current.json`）调整；Action 音量上刷新状态、音量下生成诊断报告

从旧版 `QSC定量停充` / `QSC定量停充_独立开关版`（id：`QuantitativeStopCharging` / `QuantitativeStopCharging_switch`）升级时，安装脚本会**自动卸载旧版模块**（不迁移配置），请在 WebUI 重新设置。

详细说明见 [在线文档](https://eikeitsu.github.io/QSC-Battery/) 或 `docs/`。

## 仓库结构

```text
module/          # Magisk 模块本体（与工具、文档分离）
  webroot/       # WebUI 可读源码
docs/            # 用户文档（VitePress → GitHub Pages）
  public/screenshots/  # WebUI 截图
tooling/         # 构建脚本与维护者说明（见 tooling/BUILD.md）
.github/         # CI 工作流
```

## 本地开发（维护者）

```bash
npm install
npm run dev:web
npm run build:module
```

构建说明见 [`tooling/BUILD.md`](tooling/BUILD.md)。  
发版与更新日志约定见 [`tooling/RELEASE.md`](tooling/RELEASE.md)（开发请写 `changelog.md` → `## Unreleased`）。

发版：Actions → **Release Module** → Run workflow（填写版本号），或推送 `v*` 标签。

## 致谢

感谢 **top大佬** 开源 [QSC 定量停充](https://github.com/410154425/QuantitativeStopCharging_switch_magisk)。
