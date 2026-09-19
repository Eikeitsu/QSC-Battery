# ci-dist

CI **artifact-only** channel (no update JSON — see `updates` branch).

## Layout

| Path | Contents |
|------|----------|
| `module/` | Magisk zip variants (`-full` / `-rust` / `-c` / `-sh` / `-lite`) |
| `app/` | Companion `QSC-Battery.apk` |
| `qscd/` | Daemon binaries (`qscd-rust-*` / `qscd-c-*`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: app @ 2026.09.19.ci.69 / 0b8825d434438644f2a2047bf71040df69eb2804
