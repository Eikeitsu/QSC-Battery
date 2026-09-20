# 充电控制（QSC-Battery）

面向 Magisk / KernelSU / APatch 的 **充电管理系统**：电量与温度停充、可选电流控制、分级省电、WebUI 与伴侣 APP。

模块显示名：**充电控制** · 模块 id：`QSC_Battery` · 仓库：[Eikeitsu/QSC-Battery](https://github.com/Eikeitsu/QSC-Battery)

- **在线文档**：[eikeitsu.github.io/QSC-Battery](https://eikeitsu.github.io/QSC-Battery/)
- **Releases**：[下载模块 / APP / 守护](https://github.com/Eikeitsu/QSC-Battery/releases)

> 早期曾基于「定量停充」思路起步，当前代码与交互已独立演进为完整产品，请以本仓库文档为准。

## 产品组成

| 组件             | 作用                                                         |
| ---------------- | ------------------------------------------------------------ |
| Magisk 模块      | 真正执行停充 / 限流 / 日志；开机 `service.sh` 常驻           |
| WebUI（可选）    | 模块管理器内改配置、看曲线与日志                             |
| 伴侣 APP（可选） | Compose 客户端：状态、策略、动态、主题；可内嵌进模块包       |
| qscd（可选）     | 只读 `power_supply` 事件守护，降低未插电轮询                 |
| CLI              | `/data/adb/qsc/bin/qsc`（`help` / `stats` / `diagnostic` …） |

## WebUI 预览

|                        概览                         |                       策略                        |
| :-------------------------------------------------: | :-----------------------------------------------: |
| ![概览](docs/public/screenshots/webui-overview.png) | ![策略](docs/public/screenshots/webui-config.png) |

|                      日志                      |                      我的                       |
| :--------------------------------------------: | :---------------------------------------------: |
| ![日志](docs/public/screenshots/webui-log.png) | ![我的](docs/public/screenshots/webui-more.png) |

## 能做什么

- **电量 / 温度停充**：到达阈值停充，条件恢复后再充；可关电量停充（`power_stop=110`）只留温控
- **时段 / App / 无线策略**：电量停充时段、按前台 App 停充、无线可忽略部分策略
- **电流控制（安装可选，默认关）**：模拟旁路、硬件旁路节点、慢充、温控阶梯限流、游戏限流
- **分级省电**：`power.conf` 档位 + 息屏加强 / 深睡 / 可选夜间；qscd 事件唤醒；简介按需刷新
- **事件与历史**：运行日志、充电事件、插电采样曲线、健康趋势
- **CLI**：`qsc status` / `config` / `stats` / `diagnose` / `daemon` …
- **机型适配**：MCA / preferred_switch / 测开关 / 设备档案库 / 社区预设

## 快速开始

1. 打开 [Releases](https://github.com/Eikeitsu/QSC-Battery/releases)：多数人下 **`…-full.zip`**；只要脚本可用 **`…-lite.zip`**。各文件含义见 [安装与升级 · Release 说明](docs/guide/install.md#该下哪个先看这三句)
2. 刷入模块，按音量键确认；按提示选择 WebUI / 电流控制 / 伴侣 APK / 联网下守护（lite 无 WebUI 与内嵌 APK）
3. 更新时可选保留配置；重启后用 WebUI / APP / 配置文件调整
4. Action：音量上刷新状态；音量下插电测开关 / 未插电写诊断

旧版 `QuantitativeStopCharging*` 会被自动卸载（**不迁移配置**）。

## 仓库结构

```text
module/          # Magisk 模块本体（含可选 webroot / apk）
apps/webui/      # WebUI 源码（Vue 3）
apps/android/    # 伴侣 APP（Compose）
native/          # qscd-rust / qscd-c / qsc-cli
docs/            # VitePress 用户文档 → GitHub Pages
tooling/         # 构建与发版脚本
ARCHITECTURE.md  # 冻结契约与目录约定
```

## 本地开发

```bash
npm install
npm run dev:web
npm run build:module
```

说明见 [`tooling/BUILD.md`](tooling/BUILD.md)。发版与更新日志约定见 [`tooling/RELEASE.md`](tooling/RELEASE.md)（开发写根目录 `changelog.md` → `## Unreleased`）。

发版：Actions → **Release Module**，或推送 `v*` 标签。

## 文档与致谢

完整指南见 [`docs/`](docs/) 或 [在线文档](https://eikeitsu.github.io/QSC-Battery/)。  
维护者 **许小墨**；早期思路致谢见 [致谢](docs/guide/credits.md)。
