# 充电控制（QSC-Battery）

面向 Magisk / KernelSU 的 **充电管理系统**：电量与温度停充、可选电流控制、事件驱动省电、WebUI 与伴侣 APP。

模块显示名：**充电控制** · 模块 id：`QSC_Battery` · 仓库：[Eikeitsu/QSC-Battery](https://github.com/Eikeitsu/QSC-Battery)

- **在线文档**：[eikeitsu.github.io/QSC-Battery](https://eikeitsu.github.io/QSC-Battery/)
- **Releases**：[下载模块 / APP / 守护](https://github.com/Eikeitsu/QSC-Battery/releases)

> 早期曾基于「定量停充」思路起步，当前代码与交互已独立演进为完整产品，请以本仓库文档为准。

## 产品组成

| 组件 | 作用 |
| ---- | ---- |
| Magisk 模块 | 真正执行停充 / 限流 / 日志；开机 `service.sh` 常驻 |
| WebUI（可选） | 模块管理器内改配置、看曲线与日志 |
| 伴侣 APP（可选） | Compose 客户端：状态、策略、动态、主题；可内嵌进模块包 |
| qscd（可选） | 只读 `power_supply` 事件守护，降低未插电轮询 |

## WebUI 预览

| 概览 | 策略 |
| :--: | :--: |
| ![概览](docs/public/screenshots/webui-overview.png) | ![策略](docs/public/screenshots/webui-config.png) |

| 日志 | 我的 |
| :--: | :--: |
| ![日志](docs/public/screenshots/webui-log.png) | ![我的](docs/public/screenshots/webui-more.png) |

## 能做什么

- **电量 / 温度停充**：到达阈值停充，条件恢复后再充；可关电量停充（`power_stop=110`）只留温控
- **时段 / App / 无线策略**：电量停充时段、按前台 App 停充、无线可忽略部分策略
- **电流控制（安装可选，默认关）**：模拟旁路、硬件旁路节点、慢充、温控阶梯限流、游戏限流
- **省电主循环**：`power_saver` + qscd 事件唤醒；未插电默认跳过整轮 `qsc_switch`
- **事件与历史**：运行日志、充电事件、插电采样曲线、健康趋势
- **CLI**：`bin/qsc.sh`（status / on|off / config / log / events / diagnose / daemon …）
- **机型适配**：MCA / preferred_switch / 测开关 / 设备档案库 / 社区预设

## 快速开始

1. 从 [Releases](https://github.com/Eikeitsu/QSC-Battery/releases) 下载 zip（推荐主包，需要时再在 WebUI 下守护）
2. 刷入模块，按音量键确认；选择是否安装 WebUI、电流控制、伴侣 APK、联网下守护
3. 更新时可选保留配置；重启后用 WebUI / APP / `config.conf` 调整
4. Action：音量上刷新状态；音量下插电测开关 / 未插电写诊断

旧版 `QuantitativeStopCharging*` 会被自动卸载（**不迁移配置**）。

## 仓库结构

```text
module/     # Magisk 模块本体（含可选 webroot / apk）
webui/      # WebUI 源码（Vue 3）
app/        # 伴侣 APP（Compose）
native/     # qscd Rust / C
docs/       # VitePress 用户文档 → GitHub Pages
tooling/    # 构建与发版脚本
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
