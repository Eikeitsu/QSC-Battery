# ci-dist

CI **artifact-only** channel (no update JSON — see `updates` branch).

## Layout

| Path | Contents |
|------|----------|
| `module/` | Magisk zip variants (`-full` / `-rust` / `-c` / `-sh` / `-lite`) |
| `app/` | Companion `QSC-Battery.apk` |
| `qscd/` | Daemon binaries (`qscd-rust-*` / `qscd-c-*`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: module @ 2026.09.18.ci.296 / 22cd4f483d7284914bae5a0e9867c3298f56a9cb
