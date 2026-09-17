# ci-dist

CI **artifact-only** channel (no update JSON — see `updates` branch).

## Layout

| Path | Contents |
|------|----------|
| `module/` | Magisk zip variants (`-full` / `-rust` / `-c` / `-sh` / `-lite`) |
| `app/` | Companion `QSC-Battery.apk` |
| `qscd/` | Daemon binaries (`qscd-rust-*` / `qscd-c-*`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: qscd @ 2026.09.17.ci.3 / 40c41a63b83f8beb953257ad50b3c276cf840e3e
