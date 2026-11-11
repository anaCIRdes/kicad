# KiCad "Project Status" Pane (Patch-Paket)

Erweitert den KiCad-Projektmanager um ein neues Panel **„Project Status"** (rechte Seite):

- Übersicht der zuletzt geöffneten Projekte (aus der KiCad-Dateihistorie)
- Schnellaktionen pro Projekt: **Open**, **Folder**, **Backup**, **DRC**, **ERC**, **Export**
- DRC/ERC über `kicad-cli` (JSON, `--exit-code-violations`), Cache in
  `<projekt>/.kicad_status_cache.txt`, Anzeige in der Liste als `zE/zW` (Errors/Warnings)
- Backup = komplettes Projektverzeichnis als ZIP mit Zeitstempel
- Export = Gerber + Bohrdaten + Schaltplan-PDF nach `<projekt>/production/`

## KiCad-Version

Auto-Erkennung des neuesten stabilen Releases (aktuell **10.0.8**; `*.99.*`-Dev-Tags und
Release-Kandidaten werden übersprungen). Fest wählbar: `KICAD_VERSION=10.0.8 bash ct-build-kicad.sh`
bzw. `./build.sh 10.0.8`.

## Inhalt

| Datei | Zweck |
| --- | --- |
| `src/project_status_pane.{h,cpp}` | neue Panel-Klasse |
| `patches/mod.patch` | 5-Hunk-Patch für `kicad/CMakeLists.txt`, `kicad_manager_frame.{h,cpp}` |
| `apply-patch.sh` | kopiert die Quellen und wendet den Patch an (git apply, Fallback patch(1)) |
| `wx-config-fix.sh` | installiert `/usr/local/bin/wx-config`-Wrapper (Debian 13/trixie hat kein wx-config-Binary mehr; KiCad braucht es zwingend) |
| `build.sh` | kompletter Build unter Linux Mint/Ubuntu/Debian |
| `make-deb.sh` | erzeugt aus dem Build ein installierbares `.deb` (auf dem Zielsystem ausfuehren, wegen glibc!) |
| `ct-build-kicad.sh` | kompletter Build **im Debian-13-LXC** (als root, z. B. CT107) |
| `build-win-mingw.sh` | kompletter Build unter **Windows 11 ohne Microsoft-Tools** (MSYS2 UCRT64 + MinGW, in der ucrt64.exe-Shell ausfuehren) |
| `proxmox-kicad-lxc.sh` | **OPTIONAL**, nur Proxmox-Host (legt CT automatisch an) |
| `ANLEITUNG-*.md` | Schritt-für-Schritt-Anleitungen |

## Schnellstart Proxmox LXC (empfohlen)

1. CT107 in der Proxmox-GUI manuell anlegen (Debian 13, unprivileged, rootfs auf
   **ZFS-Pool-HDD1**, vmbr0, z. B. 10.0.0.107/24, 4 Cores, 8 GB RAM)
2. SSH einrichten + zip kopieren — siehe `ANLEITUNG-PROXMOX-LXC.md`
3. Im Container: `bash ct-build-kicad.sh` (1–3 h)
4. Binaries abholen: `pct pull 107 /home/kicad/kicad-build-out/kicad ./kicad`

## Schnellstart lokales Linux

    ./build.sh          # oder: ./build.sh 10.0.8
    bash make-deb.sh    # optional: .deb-Paket fuer dieses System erzeugen
