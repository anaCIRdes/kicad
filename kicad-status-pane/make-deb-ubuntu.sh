#!/usr/bin/env bash
# make-deb-ubuntu.sh — baut auf einem Debian-13-Host (z. B. CT107) ein .deb,
# das auf Ubuntu 24.04 und Linux Mint 22 installierbar ist.
#
# Warum der Umweg: Ein .deb, das direkt auf Debian 13 (trixie, glibc 2.41) gebaut
# wird, startet auf Ubuntu 24.04 / Mint 22 (glibc 2.39) NICHT ("GLIBC_2.40 not
# found"). Deshalb wird der KOMPLETTE Build in einem Ubuntu-24.04-Chroot
# (noble, via debootstrap) ausgefuehrt: glibc 2.39, wx 3.2.4, OCCT 7.6 — das .deb
# enthaelt dadurch automatisch die richtigen noble-Abhaengigkeiten
# (libwxgtk3.2-1t64, libocct-*-7.6t64, ...).
#
# Voraussetzungen auf dem Host: root (sudo), apt, debootstrap (wird installiert),
# ~60 GB freier Platz, Zeit (erster Build mehrere Stunden — Script ist
# wiederaufsetzbar, einfach erneut starten).
#
# Aufruf:   sudo bash make-deb-ubuntu.sh [kicad-version]     z. B. 10.0.8
# Resume:   sudo bash make-deb-ubuntu.sh            (macht dort weiter, wo es war)
# Langlauf: nohup sudo bash make-deb-ubuntu.sh > build-ubuntu.log 2>&1 &
#
# Ergebnis: kicad-project-status_<version>-1_amd64.deb im Paketverzeichnis,
# installierbar auf Ubuntu 24.04+ / Linux Mint 22+ mit: sudo apt install ./....deb
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROOT="${CHROOT:-$HERE/noble-chroot}"
MIRROR="${MIRROR:-https://archive.ubuntu.com/ubuntu}"
VERSION="${1:-${KICAD_VERSION:-10.0.8}}"
PKG="kicad-project-status"

# --- root ---
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    echo ">>> bitte als root starten (sudo bash $0 $*)" >&2
    exit 1
fi
# Hinweis: Wir sind root — 'sudo' muss auf dem Host NICHT installiert sein.
command -v apt-get >/dev/null || { echo "FEHLER: apt-get nicht gefunden (Debian/Ubuntu-Container erwartet)" >&2; exit 1; }

# --- debootstrap auf dem Host ---
if ! command -v debootstrap >/dev/null 2>&1; then
    echo ">>> installiere debootstrap auf dem Host"
    apt-get update || { echo "FEHLER: apt-get update auf dem Host fehlgeschlagen" >&2; exit 1; }
    DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap
fi

# --- apt-Quellen im Chroot sicherstellen (main + universe, egal ob sources.list oder deb822) ---
fix_apt_sources() {
    if [ -f "$CHROOT/etc/apt/sources.list.d/ubuntu.sources" ]; then
        sed -i 's/^Components: main restricted$/Components: main restricted universe/; s/^Components: main$/Components: main universe/' \
            "$CHROOT/etc/apt/sources.list.d/ubuntu.sources"
    fi
    if [ -f "$CHROOT/etc/apt/sources.list" ]; then
        sed -i 's/ main restricted universe$/ main restricted universe/; s/ main restricted$/ main restricted universe/; s/ main universe$/ main universe/; s/ main$/ main universe/' \
            "$CHROOT/etc/apt/sources.list" 2>/dev/null || true
    fi
    # Fallback: universe garantiert aktiv, egal welches Format debootstrap wrote
    if ! grep -rq 'universe' "$CHROOT/etc/apt/sources.list" "$CHROOT/etc/apt/sources.list.d/" 2>/dev/null; then
        echo "deb $MIRROR noble main universe" >> "$CHROOT/etc/apt/sources.list"
        echo "deb $MIRROR noble-updates main universe" >> "$CHROOT/etc/apt/sources.list"
        echo "deb $MIRROR noble-security main universe" >> "$CHROOT/etc/apt/sources.list"
    fi
}

# --- noble-Chroot anlegen (einmalig) ---
if [ ! -f "$CHROOT/.bootstrap-done" ]; then
    echo ">>> debootstrap noble nach $CHROOT (einmalig, dauert Minuten)"
    rm -rf "$CHROOT"
    mkdir -p "$CHROOT"
    debootstrap --variant=minbase noble "$CHROOT" "$MIRROR"
    touch "$CHROOT/.bootstrap-done"
fi
fix_apt_sources

# --- Mounts + DNS (idempotent) ---
grep -q " $CHROOT/proc " /proc/mounts || mount --bind /proc "$CHROOT/proc"
grep -q " $CHROOT/sys "  /proc/mounts || mount --bind /sys  "$CHROOT/sys"
grep -q " $CHROOT/dev "  /proc/mounts || mount --bind /dev  "$CHROOT/dev"
for m in proc sys dev; do
    if ! grep -q " $CHROOT/$m " /proc/mounts; then
        echo "FEHLER: bind-mount $CHROOT/$m fehlgeschlagen — der Container braucht Mount-Rechte" >&2
        echo "        (auf dem Proxmox-Host: CT als privileged anlegen bzw. 'pct set <vmid> -features nesting=1' reicht NICHT, mount braucht CAP_SYS_ADMIN)" >&2
        exit 1
    fi
done
cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# --- /dev-Knoten einzeln durchreichen (in manchen LXC ist /dev im Chroot defekt) ---
for d in null zero full random urandom tty ptmx; do
    if [ -e "/dev/$d" ]; then
        [ -e "$CHROOT/dev/$d" ] || { rm -f "$CHROOT/dev/$d"; touch "$CHROOT/dev/$d"; }
        mount --bind "/dev/$d" "$CHROOT/dev/$d" 2>/dev/null || true
    fi
done
chroot "$CHROOT" /bin/sh -c 'echo ok > /dev/null' 2>/dev/null \
    || { echo "FEHLER: /dev/null im Chroot nicht beschreibbar — Container braucht volle Mount-Rechte (privileged)" >&2; exit 1; }

run_chroot() { chroot "$CHROOT" /bin/bash -c "set -e; $1"; }

# --- Build-Abhaengigkeiten IM CHROOT (noble-Paketnamen, einmalig) ---
if [ ! -f "$CHROOT/.deps-done" ]; then
    echo ">>> installiere Build-Abhaengigkeiten im noble-Chroot (einmalig, gross)"
    fix_apt_sources
    run_chroot "export DEBIAN_FRONTEND=noninteractive
        # gpgv fehlt in manchen minbase-Chroots -> erst ohne Signatur holen, dann gpgv installieren
        if ! command -v gpgv >/dev/null 2>&1; then
            echo '--- gpgv fehlt im Chroot, bootstrap mit --allow-insecure ...'
            apt-get -o Acquire::AllowInsecureRepositories=true -o Acquire::Retries=5 update || true
            apt-get install -y --allow-unauthenticated gpgv ca-certificates || true
        fi
        apt-get -o Acquire::Retries=5 update || { echo 'APT-UPDATE-FEHLER IM CHROOT (siehe Meldungen oben)'; exit 1; }
        echo '--- Sanity-Check nach apt update:'
        apt-cache policy ninja-build libwxgtk3.2-dev libocct-foundation-dev | grep -E '^[a-z]|Candidate:' || true
        apt-get install -y --no-install-recommends \
            build-essential cmake ninja-build git ca-certificates curl wget lld patch sudo file binutils \
            libwxgtk3.2-dev libwxgtk-webview3.2-dev libwxgtk-media3.2-dev \
            libgtk-3-dev libwebkit2gtk-4.1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
            python3-dev python3-wxgtk4.0 swig \
            libngspice0-dev libboost-dev libcairo2-dev libcurl4-openssl-dev \
            libglm-dev libprotobuf-dev protobuf-compiler libgit2-dev libnng-dev \
            libsecret-1-dev libicu-dev gettext unixodbc-dev libspnav-dev \
            libocct-foundation-dev libocct-modeling-data-dev libocct-modeling-algorithms-dev \
            libocct-data-exchange-dev libocct-visualization-dev libocct-ocaf-dev libocct-draw-dev \
            libpoppler-dev libpoppler-cpp-dev libpoppler-glib-dev libpoppler-qt6-dev \
        && touch /.deps-done"
fi

# --- Paketverzeichnis in den Chroot kopieren ---
echo ">>> kopiere Paketverzeichnis in den Chroot"
rm -rf "$CHROOT/root/kicad-status-pane"
mkdir -p "$CHROOT/root/kicad-status-pane"
tar -C "$HERE" -cf - --exclude=noble-chroot --exclude=kicad-src --exclude=kicad-build --exclude=kicad-build-out --exclude=deb-stage . \
    | tar -C "$CHROOT/root/kicad-status-pane" -xf -

# --- Build IM Chroot (SKIP_APT=1: Deps wurden oben schon installiert) ---
echo ">>> baue KiCad $VERSION im noble-Chroot (dauert beim ersten Mal Stunden; wiederaufsetzbar)"
run_chroot "cd /root/kicad-status-pane && SKIP_APT=1 KICAD_VERSION=$VERSION bash build.sh $VERSION"

# --- .deb IM Chroot erzeugen (dpkg-shlibdeps -> noble-Abhaengigkeiten) ---
echo ">>> erzeuge .deb im noble-Chroot"
run_chroot "cd /root/kicad-status-pane && KICAD_VERSION=$VERSION bash make-deb.sh"

# --- .deb auf den Host kopieren ---
DEB_IN_CHROOT="$(run_chroot "ls /root/kicad-status-pane/${PKG}_${VERSION}-1_*.deb 2>/dev/null | head -1")"
if [ -z "$DEB_IN_CHROOT" ]; then
    echo "FEHLER: .deb nicht im Chroot gefunden" >&2
    exit 1
fi
cp "$CHROOT$DEB_IN_CHROOT" "$HERE/"
DEB="$HERE/$(basename "$DEB_IN_CHROOT")"

# --- Verifikation: maximale glibc-Symbolversion <= 2.39 (noble) ---
echo ">>> Verifikation (max. GLIBC-Version der Binaries):"
MAXG="$(find "$CHROOT/root/kicad-status-pane/deb-stage/usr/local" -type f -exec sh -c 'objdump -T "$1" 2>/dev/null' _ {} \; \
    | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1 || true)"
echo "    max GLIBC: ${MAXG:-unbekannt}  (noble = GLIBC_2.39 -> OK wenn <= 2.39)"

echo
echo ">>> fertig: $DEB"
echo ">>> auf Ubuntu 24.04 / Mint 22 installieren mit:  sudo apt install $DEB"
