<div align="center">

# 充电控制 · Native

`power_supply` 事件守护与可选 CLI，交叉编译进 `module/bin/`。

[构建说明](../tooling/BUILD.md) · [主仓库](../README.md)

<br />

[![Rust](https://img.shields.io/badge/qscd-Rust-DEA584?style=for-the-badge&logo=rust&logoColor=black)](./qscd-rust/)
[![C](https://img.shields.io/badge/qscdc%20%2F%20cli-C-A8B9CC?style=for-the-badge&logo=c&logoColor=black)](./qscd-c/)

<br />

<img src="https://skillicons.dev/icons?i=rust,c,androidstudio" alt="Tech stack" />

</div>

| 路径         | 产物                                                     |
| ------------ | -------------------------------------------------------- |
| `qscd-rust/` | `qscd-arm64` / `qscd-arm`                                |
| `qscd-c/`    | `qscdc-arm64` / `qscdc-arm`                              |
| `qsc-cli/`   | 可选 native CLI                                          |
| `volkey/`    | `volkey-arm64` / `volkey-arm`（安装 + Action，防音量条） |

```bash
npm run build:native
npm run build:native:c
npm run build:native:cli
npm run build:volkey
```
