# KiCad 10.0.8 mit Project-Status-Pane unter Windows 11 bauen
## Ohne Microsoft-Tools: MSYS2 (UCRT64) + MinGW

Hinweis vorab: Seit KiCad 6 ist MSVC der offizielle Windows-Build-Weg, MSYS2/MinGW
funktioniert aber weiterhin (Legacy-Weg laut [KiCad Dev-Docs](https://dev-docs.kicad.org/en/build/windows-msys2/)).
Ohne OpenCASCADE (OCC) fehlt nur die 3D-Ansicht; 2D/EDA und das Project-Status-Pane
laufen voll. Ein fertiger `.exe`-Installer wird offiziell nur ueber NSIS/kicad-winbuilder
erzeugt — fuer den Eigenbedarf reicht die portable Installation (Schritt 6).

## 1. MSYS2 installieren

1. Installer von https://www.msys2.org laden und installieren (Standardpfad `C:\msys64`).
2. Danach die **UCRT64-Shell** starten: `C:\msys64\ucrt64.exe` (NICHT die normale MSYS2-Shell).
3. Paketliste aktualisieren (ggf. Shell einmal neu starten, wenn msys2-runtime geupdatet wurde):
   ```bash
   pacman -Syu
   ```

## 2. Abhaengigkeiten installieren (UCRT64-Shell)

Offizielle Paketliste aus den KiCad-Dev-Docs, ergaenzt um `ninja`, `gettext` und `patch`
(OpenCASCADE lassen wir weg, da wir mit `-DKICAD_USE_OCC=OFF` bauen; wxPython nur
bei Bedarf fuer Scripting — wir bauen mit `-DKICAD_SCRIPTING_WXPYTHON=OFF`).

**Zum Kopieren aufgedroeselt in 4 Bloecke** (jeder Block ist ein eigenes Kommando,
nacheinander in die UCRT64-Shell eingeben):

```bash
# Block 1: Basis + Toolchain
pacman -S --needed base-devel git patch
pacman -S --needed mingw-w64-ucrt-x86_64-toolchain
pacman -S --needed mingw-w64-ucrt-x86_64-gcc
pacman -S --needed mingw-w64-ucrt-x86_64-cmake
pacman -S --needed mingw-w64-ucrt-x86_64-ninja
```

```bash
# Block 2: Build-Hilfsprogramme
pacman -S --needed mingw-w64-ucrt-x86_64-python
pacman -S --needed mingw-w64-ucrt-x86_64-pkg-config
pacman -S --needed mingw-w64-ucrt-x86_64-swig
pacman -S --needed mingw-w64-ucrt-x86_64-gettext
```

```bash
# Block 3: KiCad-Kern-Abhaengigkeiten
pacman -S --needed mingw-w64-ucrt-x86_64-boost
pacman -S --needed mingw-w64-ucrt-x86_64-cairo
pacman -S --needed mingw-w64-ucrt-x86_64-curl
pacman -S --needed mingw-w64-ucrt-x86_64-glm
pacman -S --needed mingw-w64-ucrt-x86_64-ngspice
pacman -S --needed mingw-w64-ucrt-x86_64-zlib
pacman -S --needed mingw-w64-ucrt-x86_64-libgit2
pacman -S --needed mingw-w64-ucrt-x86_64-protobuf
pacman -S --needed mingw-w64-ucrt-x86_64-nng
```

```bash
# Block 4: wxWidgets (GUI)
pacman -S --needed mingw-w64-ucrt-x86_64-wxwidgets3.2-msw
```

Alternativ alles auf einmal (zum Markieren/Kopieren als ein Stueck):

```bash
pacman -S --needed base-devel git patch \
  mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-python mingw-w64-ucrt-x86_64-pkg-config \
  mingw-w64-ucrt-x86_64-swig mingw-w64-ucrt-x86_64-gettext \
  mingw-w64-ucrt-x86_64-boost mingw-w64-ucrt-x86_64-cairo \
  mingw-w64-ucrt-x86_64-curl mingw-w64-ucrt-x86_64-glm \
  mingw-w64-ucrt-x86_64-ngspice mingw-w64-ucrt-x86_64-zlib \
  mingw-w64-ucrt-x86_64-libgit2 mingw-w64-ucrt-x86_64-protobuf \
  mingw-w64-ucrt-x86_64-nng mingw-w64-ucrt-x86_64-wxwidgets3.2-msw
```

## 3. KiCad-Quellen holen und Patch anwenden

Das Zip `kicad-status-pane-vXX.zip` irgendwohin entpacken (z. B. `C:\Users\<du>\kicad-status-pane`).
In der UCRT64-Shell:

```bash
cd ~
git clone --depth 1 --branch 10.0.8 https://gitlab.com/kicad/code/kicad.git kicad-src
bash ~/kicad-status-pane/apply-patch.sh ~/kicad-src
```

`apply-patch.sh` kopiert `src/project_status_pane.{h,cpp}` nach `kicad-src/kicad/`
und wendet `patches/mod.patch` an (idempotent, funktioniert in MSYS2 mit `git apply`).

## 4. Konfigurieren und bauen

Alles im UCRT64-Terminal. Alternativ direkt das fertige Skript aus dem Zip:
`bash ~/kicad-status-pane/build-win-mingw.sh`

```bash
cmake -S ~/kicad-src -B ~/kicad-src/build -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_PREFIX_PATH=/ucrt64 \
  -DKICAD_USE_OCC=OFF \
  -DKICAD_USE_SPNAV=OFF \
  -DKICAD_SCRIPTING_WXPYTHON=OFF

# komplettes Default-Target bauen (dauert laenger, aber nur so ist cmake --install vollstaendig,
# z. B. images.tar.gz/Bitmaps und _kipython; fuer reines build/kicad/kicad.exe reicht --target kicad kicad-cli)
cmake --build ~/kicad-src/build -j "$(nproc)"
```

## 5. Starten (aus dem Build-Tree)

```bash
~/kicad-src/build/kicad/kicad.exe
```

Im Projektmanager erscheint rechts das Pane **„Project Status"**.

## 6. Portable Installation (empfohlen statt .exe-Installer)

```bash
cmake --install ~/kicad-src/build --prefix ~/kicad-install
# kompletten Ordner ~/kicad-install zippen oder auf einen anderen PC kopieren
~/kicad-install/bin/kicad.exe
```

Hinweis: Ein echtes Windows-Installer-`.exe` (NSIS) erzeugt man nur ueber den offiziellen
Pipeline [kicad-winbuilder](https://github.com/KiCad/kicad-winbuilder) — fuer den privaten
Gebrauch ist die portable Installation voellig ausreichend.

## 7. Bekannte Stolperfallen

- Immer die **UCRT64**-Shell (`ucrt64.exe`) verwenden, Paketnamen `mingw-w64-ucrt-x86_64-*`,
  `CMAKE_PREFIX_PATH=/ucrt64`.
- `wx-config` ist in MSYS2 vorhanden (`/ucrt64/bin/wx-config`) — kein Wrapper noetig.
- Ohne `-DKICAD_USE_OCC=OFF` wuerde CMake OpenCASCADE suchen und abbrechen.
- Build dauert je nach PC 1–3 h, Platte sollte > 40 GB frei haben.
