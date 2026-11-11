#!/usr/bin/env bash
# Applies the Project Status pane patch to a KiCad source tree.
# Usage: ./apply-patch.sh /path/to/kicad-src
# Idempotent + self-healing: resets partially patched target files to pristine
# state first (in a git clone), applies once, then verifies marker counts.
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
TARGETS="kicad/CMakeLists.txt kicad/kicad_manager_frame.h kicad/kicad_manager_frame.cpp"

IS_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && IS_GIT=1

# Already fully applied? (reverse check succeeds) -> skip
if [ "$IS_GIT" -eq 1 ] && git apply -R --whitespace=fix --check "$PATCH" 2>/dev/null; then
    echo "Patch already applied to $KICAD_SRC - skipping."
    exit 0
fi

# Reset possibly partially patched files to pristine state (safe in a fresh build clone)
if [ "$IS_GIT" -eq 1 ]; then
    git checkout -- $TARGETS 2>/dev/null || true
fi
rm -f kicad/*.rej

# Apply once: git apply first, then patch(1) with fuzz, then plain patch(1)
if [ "$IS_GIT" -eq 1 ] && git apply --whitespace=fix "$PATCH" 2>/dev/null; then
    :
elif command -v patch >/dev/null 2>&1 && patch --batch --forward -p1 --fuzz=3 < "$PATCH"; then
    :
elif command -v patch >/dev/null 2>&1; then
    patch --batch --forward -p1 < "$PATCH"
else
    echo "ERROR: neither 'git apply' nor 'patch' could apply the patch." >&2
    echo "Manual: cd $KICAD_SRC && patch --batch --forward -p1 < $PATCH" >&2
    exit 1
fi

# Verify: each inserted marker must appear exactly once
ok=1
c1="$(grep -cF 'project_status_pane.cpp' kicad/CMakeLists.txt || true)"
c2="$(grep -cF 'class PROJECT_STATUS_PANE;' kicad/kicad_manager_frame.h || true)"
c3="$(grep -cF 'PROJECT_STATUS_PANE*  m_statusPane;' kicad/kicad_manager_frame.h || true)"
c4="$(grep -cF '#include "project_status_pane.h"' kicad/kicad_manager_frame.cpp || true)"
c5="$(grep -cF 'm_statusPane = new PROJECT_STATUS_PANE' kicad/kicad_manager_frame.cpp || true)"
[ "$c1" = "1" ] && [ "$c2" = "1" ] && [ "$c3" = "1" ] && [ "$c4" = "1" ] && [ "$c5" = "1" ] || ok=0
if [ "$ok" -ne 1 ]; then
    echo "ERROR: patch verification failed (marker counts: $c1/$c2/$c3/$c4/$c5, expected 1/1/1/1/1). See kicad/*.rej" >&2
    exit 1
fi

echo "Patch applied successfully to $KICAD_SRC"
