<div align="center">

# 充电控制 · Magisk 模块

停充 / 限流 / 日志的交付面。开机 `service.sh` 常驻；可选 `webroot/`、`apk/`、`bin/qscd*`。

[安装说明](https://eikeitsu.github.io/QSC-Battery/guide/install.html) · [冻结契约](../ARCHITECTURE.md) · [主仓库](../README.md)

<br />

[![Module](https://img.shields.io/badge/id-QSC__Battery-orange?style=for-the-badge)](./module.prop)
[![Root](https://img.shields.io/badge/Magisk%20%7C%20KSU%20%7C%20APatch-informational?style=for-the-badge)](https://eikeitsu.github.io/QSC-Battery/)

<br />

<img src="https://skillicons.dev/icons?i=bash,linux,androidstudio" alt="Tech stack" />

</div>

**入口（冻结）**：`module.prop` · `service.sh` · `customize.sh` · `uninstall.sh` · `action.sh` · `META-INF/`

```bash
npm run build:module
npm run package:module:all   # full / rust / c / sh / lite
```
