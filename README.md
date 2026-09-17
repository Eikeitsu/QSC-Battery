# ci-dist

CI **artifact-only** channel (no update JSON — see `updates` branch).

## Layout

| Path | Contents |
|------|----------|
| `module/` | Magisk zip variants (`-full` / `-rust` / `-c` / `-sh` / `-lite`) |
| `app/` | Companion `QSC-Battery.apk` |
| `qscd/` | Daemon binaries (`qscd-rust-*` / `qscd-c-*`) |

Each product workflow updates **only its folder** and pushes a normal commit (history kept).

Last touch: module @ 2026.09.17.ci.289 / a826b7e8d5963a667ea35edb84107ab5e5a75600
