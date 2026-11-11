# Anleitung: Patched KiCad unter Linux Mint / Ubuntu / Debian bauen

```bash
unzip kicad-status-pane.zip
cd kicad-status-pane
./build.sh                 # neueste stabile Version (auto, aktuell 10.0.8)
# oder fest: ./build.sh 10.0.8
```

`build.sh` installiert alle Build-Abhängigkeiten (apt), klont KiCad, wendet den Patch an
und baut mit Ninja (erste Mal mehrere Stunden).

Start: `./kicad-build/kicad/kicad` — im Projektmanager rechts das Panel **„Project Status"**
über das View-Menü einblenden, falls eingeklappt.

## .deb-Paket erzeugen (zum Verteilen/Installieren per dpkg/apt)

```bash
./build.sh                 # muss auf DEM Zielsystem laufen (Mint 22), siehe unten
bash make-deb.sh           # erzeugt kicad-project-status_10.0.8-1_amd64.deb
sudo apt install ./kicad-project-status_10.0.8-1_amd64.deb
```

**Wichtig:** Das .deb muss auf dem Zielsystem gebaut werden! Ein .deb aus dem
Debian-13-CT (Proxmox) funktioniert auf Mint 22 **nicht**, weil Debian 13 eine
neuere glibc (2.41) hat als Ubuntu 24.04/Mint 22 (2.39) — die Binaries wuerden
sonst mit `version 'GLIBC_2.40' not found` abstuerzen. Deshalb: auf dem Mint-22-
Rechner `build.sh` + `make-deb.sh` ausfuehren, das fertige .deb dann z. B. per
SFTP auf andere Mint-22-Rechner kopieren und dort mit `sudo apt install ./...deb`
installieren.

Das .deb installiert nach `/usr/local` (Binaries, Libs, Ressourcen,
Desktop-Dateien) und registriert `/usr/local/lib` per `ldconfig`.
