# Anleitung: Patched KiCad unter Windows 11 bauen (MSYS2 + MSVC)

Empfohlener Weg: offizieller KiCad-Windows-Build mit MSYS2/MSVC
(siehe https://dev-docs.kicad.org/en/build/windows-msys2/).

1. MSYS2 (UCRT64) installieren und KiCad-vcpkg-Umgebung aufsetzen (gemäß Doku).
2. KiCad-Quellen klonen (neuestes stabiles Release, aktuell 10.0.8):
   ```powershell
   git clone --depth 1 --branch 10.0.8 https://gitlab.com/kicad/code/kicad.git kicad-src
   ```
3. Patch anwenden:
   ```powershell
   copy src\project_status_pane.h kicad-src\kicad\
   copy src\project_status_pane.cpp kicad-src\kicad\
   cd kicad-src
   git apply ..\patches\mod.patch
   ```
4. Konfigurieren + bauen:
   ```powershell
   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKICAD_USE_SPNAV=OFF
   cmake --build build --target kicad kicad-cli
   ```
5. Start: `build\kicad\kicad.exe`
