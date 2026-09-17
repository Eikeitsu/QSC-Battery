# ci-dist

CI **artifact-only** channel (no update JSON — see `updates` branch).

## Layout

| Path | Contents |
|------|----------|
| `module/` | Magisk zip variants (`-full` / `-rust` / `-c` / `-sh` / `-lite`) |
| `app/` | Companion `QSC-Battery.apk` |
| `qscd/` | Daemon binaries (`qscd-rust-*` / `qscd-c-*`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: qscd @ 2026.09.17.ci.5 / 49ee9b994359f4966f9e5abb3b49566eb8295747
