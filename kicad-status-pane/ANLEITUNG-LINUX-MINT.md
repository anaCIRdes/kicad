# Anleitung: Patched KiCad unter Linux Mint / Ubuntu / Debian bauen

```bash
unzip kicad-status-pane.zip
cd kicad-status-pane
./build.sh                 # neueste stabile Version (auto, aktuell 10.0.8)
# oder fest: ./build.sh 10.0.8
```

build.sh installiert alle Build-Ab2讧igkeiten (apt), klont KiCad, wendet den Patch an
und baut mit Ninja (erste Mal mehrere Stunden).

Start: `./kicad-build/kicad/kicad` — im Projektmanager rechts das Panel **„Project Status"**
über das View-Menó einblenden, falls eingeklappt.
