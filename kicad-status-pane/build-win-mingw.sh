#!/usr/bin/env bash
# Builds patched KiCad (Project Status pane) on Windows 11 WITHOUT Microsoft tools,
# using MSYS2 UCRT64 + MinGW. Run inside the UCRT64 shell (C:\msys64\ucrt64.exe):
#   bash /c/Users/<you>/kicad-status-pane/build-win-mingw.sh
# Optional: KICAD_VERSION=10.0.8 bash build-win-mingw.sh
set -euo pipefail

KICAD_VERSION="${KICAD_VERSION:-10.0.8}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${KICAD_SRC:-$HOME/kicad-src}"
BUILD="$SRC/build"
PREFIX="${KICAD_PREFIX:-$HOME/kicad-install}"

echo ">>> KiCad version: $KICAD_VERSION"

if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$KICAD_VERSION" https://gitlab.com/kicad/code/kicad.git "$SRC"
else
    echo ">>> reusing existing clone at $SRC"
fi

# copy pane sources + apply patch (idempotent)
bash "$HERE/apply-patch.sh" "$SRC"

# configure (no OCC, no spacenav, no wxPython scripting -> no Microsoft tools needed)
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH=/ucrt64 \
    -DKICAD_USE_OCC=OFF \
    -DKICAD_USE_SPNAV=OFF \
    -DKICAD_SCRIPTING_WXPYTHON=OFF

# full default-target build (so cmake --install gets images.tar.gz etc.)
cmake --build "$BUILD" -j "$(nproc)"

# portable install
cmake --install "$BUILD" --prefix "$PREFIX"

echo ">>> done."
echo ">>> start from build tree : $BUILD/kicad/kicad.exe"
echo ">>> start installed      : $PREFIX/bin/kicad.exe"
