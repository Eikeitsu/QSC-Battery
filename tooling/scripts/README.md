# Tooling scripts map

Scripts stay at `tooling/scripts/*.mjs|*.py|*.sh` so npm / CI entry paths stay stable.
Logical groups (new scripts should land in the matching concern; optional physical subfolders may appear later):

| Group | Examples |
| --- | --- |
| **build** | `build-web.mjs`, `build-native*.mjs`, `lint-shell.mjs` |
| **package** | `package-module.mjs`, `package-app.mjs`, `verify-module-zips.mjs`, `*-packaging-deps.sh` |
| **release** | `resolve-release-version.py`, `stamp-ci-module-version.py`, `publish-*.sh`, `sync-package-version.mjs` |
| **test** | `test-shell.mjs`, `test-hot-update.mjs`, `test-service-recovery.mjs`, `run-python.mjs` |
| **dev** | `dev/` — one-shot splitters / local helpers; not part of the default contributor path |

Shared helpers: `lib/`.

Version sync: after bumping `module/module.prop` `version=`, run `node tooling/scripts/sync-package-version.mjs` (also recommended from release stamp).
