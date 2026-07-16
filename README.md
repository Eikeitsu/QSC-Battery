# QSC 定量停充（WebUI 版）

基于 **top大佬** 原作，由 **许小墨** 维护 WebUI。

到达指定电量 / 温度自动停充与恢复，支持 Magisk / KernelSU WebUI 配置。

## 仓库结构

```text
module/          # Magisk 模块本体（与工具、文档分离）
  webroot/       # WebUI 可读源码
docs/            # 用户文档（VitePress → GitHub Pages）
tooling/         # 构建脚本与维护者说明（见 tooling/BUILD.md）
.github/         # CI 工作流
```

## 快速开始（用户）

1. 从 [Releases](https://github.com/410154425/QuantitativeStopCharging_switch_magisk/releases) 下载 zip
2. 刷入模块并重启
3. 打开 WebUI 调整阈值

详细说明见在线文档（GitHub Pages）或 `docs/`。

## 本地开发（维护者）

```bash
npm install
npm run dev:web
npm run build:module
```

构建说明见 [`tooling/BUILD.md`](tooling/BUILD.md)。

发版：Actions → **Release Module** → Run workflow（填写版本号），或推送 `v*` 标签。

## 致谢

感谢 **top大佬** 开源 [QSC 定量停充](https://github.com/410154425/QuantitativeStopCharging_switch_magisk)。
