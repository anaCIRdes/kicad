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
if command -v dpkg-shlibdeps >/dev/null && command -v file >/dev/null; then
    BINARIES="$(cd "$STAGE" && find usr -type f -exec sh -c 'file -b "$1" 2>/dev/null | grep -q ELF && echo "$1"' _ {} \; 2>/dev/null || true)"
    if [ -n "$BINARIES" ]; then
        # Ausgabe parsen: "dependency: a (>= x), b" ODER "shlibs:Depends=a, b"
        RAW="$(cd "$STAGE" && dpkg-shlibdeps -O $BINARIES 2>/dev/null || true)"
        DEPS="$(printf '%s\n' "$RAW" \
            | sed -n 's/^[A-Za-z:_-]*[=:]\s*//p' \
            | tr ',' '\n' | sed 's/^ *//;s/ *$//;s/ *(.*$//' \
            | grep -v '^\*' | grep -v '^$' | sort -u | paste -sd, -)"
    fi
fi
if [ -z "$DEPS" ]; then
    echo "WARN: dpkg-shlibdeps lieferte nichts — Fallback mit festen noble-Paketnamen" >&2
    DEPS="libc6, libwxgtk3.2-1t64, python3, libngspice0, libocct-foundation-7.6t64, libocct-modeling-data-7.6t64, libocct-modeling-algorithms-7.6t64, libocct-data-exchange-7.6t64, libocct-visualization-7.6t64, libocct-ocaf-7.6t64, libocct-draw-7.6t64, libboost-locale1.83.0, libboost-test1.83.0, libprotobuf32, libgit2-1.7, libnng1.7, libsecret-1-0, libpoppler-qt6-1, libwebkit2gtk-4.1-37, libgtk-3-0t64, libcairo2, libcurl4t64, libicu74, unixodbc, libspnav0"
fi
# Sicherheit: keine Globs in Depends erlaubt
DEPS="$(printf '%s' "$DEPS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '\*' | paste -sd, -)"

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
