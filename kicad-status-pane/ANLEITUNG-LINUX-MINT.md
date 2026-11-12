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

### .deb fuer Ubuntu 24.04 / Mint 22 direkt AUF CT107 (Debian 13) bauen

Auf CT107 (root) genuegt:

```bash
cd kicad-status-pane
sudo bash make-deb-ubuntu.sh 10.0.8        # erster Lauf: mehrere Stunden
# Langlauf: nohup sudo bash make-deb-ubuntu.sh 10.0.8 > build-ubuntu.log 2>&1 &
# danach:   tail -f build-ubuntu.log         # Fortschritt verfolgen
# Abbruch + Resume: Script einfach erneut starten, cmake baut dort weiter
```

`make-deb-ubuntu.sh` richtet automatisch ein **Ubuntu-24.04-Chroot** (noble, via
debootstrap) ein, installiert darin die Build-Abhaengigkeiten (wx 3.2.4,
OCCT 7.6, ...), baut KiCad darin und erzeugt das .deb mit `dpkg-shlibdeps` im
Chroot. **Troubleshooting:** Meldet apt im Chroot `Unable to locate package ...`
/ `no installation candidate`, waren die Paketlisten leer (debootstrap trug
nur `main` ein) — ab v24 korrigiert das Skript die Quellen (main+universe,
sources.list und deb822) automatisch und `apt-get update` bricht mit klarer
Fehlermeldung ab. Einfach erneut starten, es setzt automatisch fort. Ergebnis: `kicad-project-status_10.0.8-1_amd64.deb` — dieses .deb
linkt gegen glibc 2.39 und laeuft auf **Ubuntu 24.04+ und Linux Mint 22+**:

```bash
sudo apt install ./kicad-project-status_10.0.8-1_amd64.deb
```

Das .deb installiert nach `/usr/local` (Binaries, Libs, Ressourcen,
Desktop-Dateien) und registriert `/usr/local/lib` per `ldconfig`.
