# updates

APP / WebUI update **metadata only** (`stable` / `prerelease` / `ci`).

- Magisk / KSU / APatch still use **GitHub Pages** `update.json`.
- CI binaries live on **`ci-dist`** (`module/` / `app/` / `qscd/`); prerelease packages on GitHub Releases; stable package URLs usually point at Pages.
- Each product workflow updates only its JSON and pushes a normal commit.
