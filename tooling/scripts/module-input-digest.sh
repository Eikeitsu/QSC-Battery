#!/usr/bin/env bash
# Compute packaging input digest (deps + module sources excluding generated webroot copy noise).
# Prints DIGEST=<hex> for shell eval / GITHUB_OUTPUT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TMP="$(mktemp)"
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

{
  # resolved deps
  for f in \
    module/bin/qscd-arm64 module/bin/qscd-arm \
    module/bin/qscdc-arm64 module/bin/qscdc-arm \
    release/QSC-Battery.apk; do
    if [ -f "$f" ]; then
      sha256sum "$f"
    else
      echo "MISSING $f"
    fi
  done

  if [ -d .build/webroot ]; then
    find .build/webroot -type f | sort | xargs -r sha256sum
  elif [ -d module/webroot ]; then
    find module/webroot -type f | sort | xargs -r sha256sum
  else
    echo "MISSING webroot"
  fi

  # module sources (not webroot / not built binaries)
  find module \
    \( -path 'module/webroot' -o -path 'module/webroot/*' \
       -o -name 'qscd-arm64' -o -name 'qscd-arm' \
       -o -name 'qscdc-arm64' -o -name 'qscdc-arm' \
       -o -name 'qsc-arm64' -o -name 'qsc-arm' \) -prune -o \
    -type f -print | sort | xargs -r sha256sum
} >"$TMP"

DIGEST="$(sha256sum "$TMP" | awk '{print $1}')"
echo "DIGEST=$DIGEST"
echo "$DIGEST"
