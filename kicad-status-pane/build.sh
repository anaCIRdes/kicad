#!/usr/bin/env bash
# Builds a patched KiCad (with the Project Status pane) on Linux Mint / Ubuntu / Debian.
# Usage: ./build.sh [version]     e.g. ./build.sh 10.0.8   (default: newest stable, auto-detected)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/kicad-src"
BUILD="$HERE/kicad-build"
OUT="$HERE/kicad-build-out"

# --- KiCad version: newest stable tag (exclude *.99.* dev and rc tags), fallback 10.0.8 ---
if [ $# -ge 1 ]; then
    KICAD_VERSION="$1"
else
    KICAD_VERSION="${KICAD_VERSION:-$(git ls-remote --tags --refs https://gitlab.com/kicad/code/kicad.git \
        | awk -F/ '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^[0-9]+\.99\.' \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)}"
    KICAD_VERSION="${KICAD_VERSION:-10.0.8}"
fi
echo ">>> KiCad version: $KICAD_VERSION"

# --- dependencies (Debian/Ubuntu/Mint; ngspice dev pkg is libngspice0-dev on trixie) ---
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates curl lld patch \
    libwxgtk3.2-dev libwxgtk-webview3.2-dev libwxgtk-media3.2-dev \
    libgtk-3-dev libwebkit2gtk-4.1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    python3-dev python3-wxgtk4.0 swig \
    libngspice0-dev libboost-dev libcairo2-dev libcurl4-openssl-dev \
    libglm-dev libprotobuf-dev protobuf-compiler libgit2-dev libnng-dev \
    libsecret-1-dev libicu-dev gettext unixodbc-dev \
    libpoppler-dev libpoppler-cpp-dev libpoppler-glib-dev libpoppler-qt6-dev

# --- Debian 13 "trixie" ships no /usr/bin/wx-config binary -> install wrapper if missing ---
if ! command -v wx-config >/dev/null 2>&1; then
    sudo bash "$HERE/wx-config-fix.sh"
fi

# --- source ---
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$KICAD_VERSION" https://gitlab.com/kicad/code/kicad.git "$SRC"
else
    echo ">>> reusing existing clone at $SRC"
fi

# --- patch ---
bash "$HERE/apply-patch.sh" "$SRC"

# --- configure + build ---
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_FLAGS="-fuse-ld=lld" \
    -DKICAD_SCRIPTING_PYTHON3=ON \
    -DKICAD_USE_OCC=OFF \
    -DKICAD_USE_SPNAV=OFF
cmake --build "$BUILD" --target kicad kicad-cli -j"$(nproc)"

mkdir -p "$OUT"
cp "$BUILD/kicad/kicad" "$OUT/" 2>/dev/null || true
cp "$BUILD/kicad-cli/kicad-cli" "$OUT/" 2>/dev/null || true
echo ">>> done. Binaries in $OUT ; start with: $BUILD/kicad/kicad"
