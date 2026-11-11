#!/usr/bin/env bash
# Applies the Project Status pane patch to a KiCad source tree.
# Usage: ./apply-patch.sh /path/to/kicad-src
# Idempotent: if the patch is already applied, it is skipped.
# Tries git apply first, then patch(1) with fuzz (--batch --forward, never asks).
set -euo pipefail

KICAD_SRC="${1:-}"
if [ -z "$KICAD_SRC" ]; then
    echo "Usage: $0 /path/to/kicad-src" >&2
    exit 1
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$KICAD_SRC/kicad" ]; then
    echo "ERROR: $KICAD_SRC does not look like a KiCad source tree (no kicad/ subdir)." >&2
    exit 1
fi

cp "$HERE/src/project_status_pane.h"   "$KICAD_SRC/kicad/"
cp "$HERE/src/project_status_pane.cpp" "$KICAD_SRC/kicad/"

cd "$KICAD_SRC"
PATCH="$HERE/patches/mod.patch"
IS_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1

# Already applied? (reverse check succeeds) -> skip
if [ "$IS_GIT" -eq 1 ] && git apply -R --whitespace=fix --check "$PATCH" 2>/dev/null; then
    echo "Patch already applied to $KICAD_SRC - skipping."
    exit 0
fi

if [ "$IS_GIT" -eq 1 ] && git apply --whitespace=fix --check "$PATCH" 2>/dev/null; then
    git apply --whitespace=fix "$PATCH"
elif command -v patch >/dev/null 2>&1 \
    && patch --batch --forward -p1 --fuzz=3 --dry-run < "$PATCH" >/dev/null 2>&1; then
    patch --batch --forward -p1 --fuzz=3 < "$PATCH"
elif command -v patch >/dev/null 2>&1; then
    patch --batch --forward -p1 < "$PATCH"
else
    echo "ERROR: neither 'git apply' nor 'patch' could apply the patch." >&2
    echo "Manual: cd $KICAD_SRC && patch --batch --forward -p1 < $PATCH" >&2
    exit 1
fi

# Verify: in a git tree the reverse check must now succeed
if [ "$IS_GIT" -eq 1 ]; then
    if ! git apply -R --whitespace=fix --check "$PATCH" 2>/dev/null; then
        echo "ERROR: patch verification failed (reverse check) in $KICAD_SRC" >&2
        exit 1
    fi
fi

echo "Patch applied successfully to $KICAD_SRC"
