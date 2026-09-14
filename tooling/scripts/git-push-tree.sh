#!/usr/bin/env bash
# Merge a source tree into a branch tip and push WITHOUT force.
#
# Usage:
#   git-push-tree.sh <branch> <source-dir> <commit-message>
#
# - Clones existing branch (or creates orphan if missing)
# - Copies source-dir contents over the worktree (keeps unrelated files)
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
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if git clone --depth 80 --branch "$BRANCH" "$REMOTE" "$WORK" 2>/dev/null; then
  echo "git-push-tree: cloned $BRANCH"
else
  echo "git-push-tree: creating orphan $BRANCH"
  git clone --depth 1 "$REMOTE" "$WORK"
  cd "$WORK"
  git checkout --orphan "$BRANCH"
  git rm -rf . >/dev/null 2>&1 || true
  # orphan may still have leftover untracked; clear
  find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
fi

cd "$WORK"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Overlay source onto tip (preserve files not present in SRC)
cp -a "$SRC"/. .

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
