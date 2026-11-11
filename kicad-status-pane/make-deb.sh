#!/usr/bin/env bash
# make-deb.sh — erzeugt ein installierbares .deb aus dem gebauten, gepatchten KiCad.
#
# WICHTIG: Das .deb MUSS auf dem Zielsystem gebaut werden (z. B. Linux Mint 22 /
# Ubuntu 24.04), NICHT im Debian-13-CT: Binaries mit neuerer glibc laufen auf
# aelteren Systemen nicht ("version `GLIBC_2.40' not found").
#
# Voraussetzung: build.sh wurde auf DIESER Maschine bereits ausgefuehrt
# (Build-Verzeichnis ./kicad-build existiert).
#
# Ergebnis:  kicad-project-status_<version>-1_<arch>.deb  im Paketverzeichnis
# Install:   sudo apt install ./kicad-project-status_*_amd64.deb
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/kicad-build"
VERSION="${KICAD_VERSION:-10.0.8}"
PKG="kicad-project-status"
PREFIX="/usr/local"          # gleich wie build.sh --prefix, damit kompilierte Pfade passen
STAGE="$HERE/deb-stage"

if [ ! -f "$BUILD/CMakeCache.txt" ]; then
    echo "FEHLER: $BUILD existiert nicht. Bitte zuerst ./build.sh auf dieser Maschine ausfuehren." >&2
    exit 1
fi
if ! command -v dpkg-deb >/dev/null; then
    echo "FEHLER: dpkg-deb nicht gefunden (nur auf Debian/Ubuntu/Mint verfuegbar)." >&2
    exit 1
fi

ARCH="$(dpkg --print-architecture)"
DEB="$HERE/${PKG}_${VERSION}-1_${ARCH}.deb"

echo ">>> Stage nach $STAGE (Prefix $PREFIX)"
rm -rf "$STAGE"
mkdir -p "$STAGE"
DESTDIR="$STAGE" cmake --install "$BUILD" --prefix "$PREFIX"

mkdir -p "$STAGE/DEBIAN"

# Abhaengigkeiten best-effort ermitteln (dpkg-shlibdeps ueber alle ELF-Binaries)
DEPS=""
if command -v dpkg-shlibdeps >/dev/null; then
    BINARIES="$(cd "$STAGE" && find usr -type f -exec sh -c 'file -b "$1" | grep -q ELF && echo "$1"' _ {} \; 2>/dev/null || true)"
    if [ -n "$BINARIES" ]; then
        DEPS="$(cd "$STAGE" && dpkg-shlibdeps -O $BINARIES 2>/dev/null \
            | sed -n 's/^dependency: //p' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | sort -u | paste -sd, - || true)"
    fi
fi
# Fallback: statische Kern-Abhaengigkeiten (wxWidgets, Python, OpenCASCADE)
if [ -z "$DEPS" ]; then
    DEPS="libwxgtk3.2-1t64 | libwxgtk3.2-1 | libwxgtk3.2-0, python3, libopencascade7, libngspice0, liboce-* | libocct-*"
fi

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION-1
Section: electronics
Priority: optional
Architecture: $ARCH
Maintainer: anaCIRdes <noreply@github.com>
Depends: $DEPS
Description: KiCad $VERSION mit "Project Status"-Panel (inoffizieller Patch)
 KiCad $VERSION, kompiliert aus dem offiziellen Quellcode mit zusaetzlichem
 Panel im Projektmanager (Multi-Projekt-Uebersicht mit Schnellaktionen:
 Oeffnen, Ordner, Backup, DRC, ERC, Export).
 Installiert nach $PREFIX (Binaries, Bibliotheken, Ressourcen, Desktop-Dateien).
EOF

# postinst: ldconfig fuer die Libs unter $PREFIX/lib
cat > "$STAGE/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
echo "$PREFIX/lib" > /etc/ld.so.conf.d/kicad-project-status.conf
ldconfig
update-desktop-database -q "$PREFIX/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$PREFIX/share/icons/hicolor" 2>/dev/null || true
# KiCad-Ressourcen liegen wo kompiliert: $PREFIX/share/kicad
echo ">>> KiCad installiert. Start: $PREFIX/bin/kicad"
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

cat > "$STAGE/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = "remove" ]; then
    rm -f /etc/ld.so.conf.d/kicad-project-status.conf
    ldconfig
fi
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postrm"

echo ">>> dpkg-deb --build"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo
echo ">>> fertig: $DEB"
echo ">>> installieren mit:  sudo apt install $DEB"
echo ">>> deinstallieren:   sudo apt remove $PKG"
