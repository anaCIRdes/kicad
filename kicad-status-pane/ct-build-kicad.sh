#!/usr/bin/env bash
# Builds a patched KiCad (Project Status pane) inside a Debian 13 LXC container.
# Run as root inside the container, e.g. CT107 "kicadbuilder":
#   bash ct-build-kicad.sh
# Optional: KICAD_VERSION=10.0.8 bash ct-build-kicad.sh   (default: newest stable, auto-detected)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: please run as root inside the container (no sudo needed for root)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-/home/kicad}"
SRC="$WORK_DIR/kicad-src"
BUILD="$WORK_DIR/kicad-build"
OUT="$WORK_DIR/kicad-build-out"
mkdir -p "$WORK_DIR"

# --- KiCad version: newest stable tag (exclude *.99.* dev and rc tags), fallback 10.0.8 ---
if [ -z "${KICAD_VERSION:-}" ]; then
    KICAD_VERSION="$(git ls-remote --tags --refs https://gitlab.com/kicad/code/kicad.git \
        | awk -F/ '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^[0-9]+\.99\.' \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    KICAD_VERSION="${KICAD_VERSION:-10.0.8}"
fi
echo ">>> KiCad version: $KICAD_VERSION"

# --- dependencies (Debian 13 "trixie": ngspice dev pkg is libngspice0-dev, NOT libngspice-dev) ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates curl lld patch \
    libwxgtk3.2-dev libwxgtk-webview3.2-dev libwxgtk-media3.2-dev \
    libgtk-3-dev libwebkit2gtk-4.1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    python3-dev python3-wxgtk4.0 swig \
    libngspice0-dev libboost-dev libcairo2-dev libcurl4-openssl-dev \
    libglm-dev libprotobuf-dev protobuf-compiler libgit2-dev libnng-dev \
    libsecret-1-dev libicu-dev gettext unzip

# --- trixie ships no /usr/bin/wx-config binary -> install wrapper (KiCad's FindwxWidgets needs it) ---
bash "$SCRIPT_DIR/wx-config-fix.sh"

# --- source (reuse existing clone) ---
if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$KICAD_VERSION" https://gitlab.com/kicad/code/kicad.git "$SRC"
else
    echo ">>> reusing existing clone at $SRC"
fi

# --- patch (git apply first, patch(1) fallback) ---
bash "$SCRIPT_DIR/apply-patch.sh" "$SRC"

# --- configure + build (-DKICAD_USE_SPNAV=OFF is required without libspnav) ---
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
echo ">>> done. Binaries in $OUT"
