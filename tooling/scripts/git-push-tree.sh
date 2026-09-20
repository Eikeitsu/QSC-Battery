#!/usr/bin/env bash
# Merge a source tree into a branch tip and push WITHOUT force.
#
# Usage:
#   git-push-tree.sh <branch> <source-dir> <commit-message>
#
# - Clones existing branch (or creates orphan if missing)
# - Copies source-dir contents over the worktree (keeps unrelated files)
# - For **/state.json：与 tip 深合并（SRC 键覆盖），避免并发发布丢字段
# - Commits only when there are changes
# - Pushes with rebase retry (no -f)
#
# Env: GITHUB_TOKEN, GITHUB_REPOSITORY
set -euo pipefail

BRANCH="${1:?branch}"
SRC="${2:?source-dir}"
MSG="${3:?commit message}"

OWNER_REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN required}"
REMOTE="https://x-access-token:${TOKEN}@github.com/${OWNER_REPO}.git"

if [ ! -d "$SRC" ]; then
  echo "git-push-tree: source not a directory: $SRC" >&2
  exit 1
fi

WORK="$(mktemp -d)"
SAVED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$SAVED"; }
trap cleanup EXIT

if git clone --depth 80 --branch "$BRANCH" "$REMOTE" "$WORK" 2>/dev/null; then
  echo "git-push-tree: cloned $BRANCH"
else
  echo "git-push-tree: creating orphan $BRANCH"
  git clone --depth 1 "$REMOTE" "$WORK"
  cd "$WORK"
  git checkout --orphan "$BRANCH"
  git rm -rf . >/dev/null 2>&1 || true
  find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
fi

cd "$WORK"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# 保存 tip 上已有 state.json，overlay 后与 SRC 合并
while IFS= read -r -d '' f; do
  rel="${f#./}"
  mkdir -p "$SAVED/$(dirname "$rel")"
  cp -a "$f" "$SAVED/$rel"
done < <(find . -name state.json -print0 2>/dev/null || true)

# Overlay source onto tip (preserve files not present in SRC)
cp -a "$SRC"/. .

# state.json：tip ∪ SRC（SRC 覆盖同名键）
export SAVED SRC
python3 - <<'PY'
import json, os, pathlib

saved_root = pathlib.Path(os.environ["SAVED"])
src_root = pathlib.Path(os.environ["SRC"])
work = pathlib.Path(".")

def load(p: pathlib.Path) -> dict:
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}

for src_state in src_root.rglob("state.json"):
    rel = src_state.relative_to(src_root)
    tip = load(saved_root / rel)
    patch = load(src_state)
    if not patch and not tip:
        continue
    merged = dict(tip)
    merged.update(patch)
    out = work / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"git-push-tree: merged {rel}")
PY

git add -A
if git diff --cached --quiet; then
  echo "git-push-tree: no changes on $BRANCH"
  exit 0
fi

git commit -m "$MSG"

for attempt in 1 2 3 4 5 6; do
  if git push origin "HEAD:refs/heads/${BRANCH}"; then
    echo "git-push-tree: pushed $BRANCH"
    exit 0
  fi
  echo "git-push-tree: push failed (attempt $attempt), rebase…"
  git fetch origin "$BRANCH" || true
  if git rebase "origin/${BRANCH}"; then
    sleep "$((attempt))"
    continue
  fi
  echo "git-push-tree: rebase conflict, abort" >&2
  git rebase --abort 2>/dev/null || true
  exit 1
done

echo "git-push-tree: exhausted retries" >&2
exit 1
