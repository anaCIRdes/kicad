# KiCad 10.0.8 mit Project-Status-Pane unter Windows 11 bauen
## Offizieller Weg: Visual Studio (MSVC) + vcpkg + CMake-Presets

Quelle: [KiCad Dev-Docs "Windows (Visual Studio)"](https://dev-docs.kicad.org/en/build/windows-msvc/).
Das ist der offizielle, von KiCad selbst verwendete Release-Pfad (seit KiCad 6) —
alle Funktionen inkl. 3D (OpenCASCADE) und Python-Scripting sind inklusive,
unser Project-Status-Pane kompiliert 1:1 mit.

**Platzbedarf: ca. 60 GB frei** (11 GB Visual Studio, 5 GB vcpkg, 4 GB Source, 40 GB ein Build).
Kurze Pfade nahe am Laufwerkswurzel verwenden (z. B. `C:\dev\...`), wegen 260-Zeichen-Pfadlimit.

## 1. Werkzeuge installieren

```powershell
# Visual Studio 2022 Community (gratis) mit Workload "Desktopentwicklung mit C++"
winget install --id Microsoft.VisualStudio.2022.Community -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
# (VS 2026 geht auch: Microsoft.VisualStudio.Community; CI nutzt VS 2022)

# Git for Windows
winget install --id Git.Git -e

# Windows-Longpaths aktivieren (einmalig, admin-PowerShell), dann neu starten
New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force
```

Computer nach der VS-Installation neu starten. Neues Terminal oeffnen, damit `git` im PATH ist.

**Variante ohne VS-IDE (nur Kommandozeile / VS Code):** Statt Visual Studio Community genuegen
allein die **Visual Studio Build Tools 2022** (gratis, deutlich kleiner: Workload
"Desktopentwicklung mit C++" bzw. MSVC v143 + Windows SDK + CMake/Ninja). VS Code selbst ist
nur ein Editor und enthaelt keinen Compiler — mit Build Tools + VS Code samt den Extensions
"C/C++" und "CMake Tools" steuerst du aber exakt dieselben Presets (siehe Schritt 4/5).

## 2. Quellcode holen (10.0.8) und Patch anwenden

```powershell
cd C:\dev
git clone --depth 1 --branch 10.0.8 https://gitlab.com/kicad/code/kicad.git kicad
# Patch-Paket entpacken, z. B. nach C:\dev\kicad-status-pane
cd C:\dev\kicad
# Pane-Quellen kopieren und Patch anwenden (git apply, aus Git-Bash oder PowerShell):
copy C:\dev\kicad-status-pane\src\project_status_pane.h kicad\
copy C:\dev\kicad-status-pane\src\project_status_pane.cpp kicad\
git apply C:\dev\kicad-status-pane\patches\mod.patch
# (in Git Bash alternativ: bash /c/dev/kicad-status-pane/apply-patch.sh /c/dev/kicad)
```

## 3. vcpkg einrichten (Abhaengigkeiten)

```powershell
cd C:\dev
git clone https://github.com/microsoft/vcpkg.git vcpkg
cd vcpkg
# exakt den Commit auschecken, den KiCad-CI verwendet (aktuell lt. Doku; immer in
# https://github.com/KiCad/kicad-win-builder/blob/master/build.ps1 unter \$vcpkgCommit nachsehen):
git checkout 66c0373dc7fca549e5803087b9487edfe3aca0a1
.\bootstrap-vcpkg.bat -disableMetrics
```

Eigener vcpkg-Clone ist wichtig (nicht die in VS integrierte Kopie): nur so laesst sich der
CI-Commit pinnen und Prebuilt-Pakete nutzen.

## 4. CMake-Presets konfigurieren

```powershell
cd C:\dev\kicad
copy CMakePresets.json.sample CMakePresets.json
notepad CMakePresets.json
```

Im Preset `msvc` folgendes anpassen (Werte mit Forward-Slashes):

```json
"environment": {
  "VCPKG_ROOT": "C:/dev/vcpkg",
  "VCPKG_BINARY_SOURCES": "default;nuget,https://gitlab.com/api/v4/projects/27426693/packages/nuget/index.json,read"
},
"cacheVariables": {
  "KICAD_BUILD_QA_TESTS": "ON",
  "VCPKG_OVERLAY_TRIPLETS": "${sourceDir}/tools/custom_vcpkg_triplets"
}
```

`VCPKG_BINARY_SOURCES` + `VCPKG_OVERLAY_TRIPLETS` sorgen dafuer, dass vcpkg KiCads
Prebuilt-Pakete aus dem oeffentlichen Feed holt ("Restored 143 package(s) from NuGet" statt
alles von Quelle zu bauen). Ohne einen der beiden Werte baut vcpkg stundenlang selbst.

## 5. Bauen

**In Visual Studio:** Ordner `C:\dev\kicad` oeffnen ("Lokalen Ordner oeffnen"), in der
Toolbar-Konfiguration **Win64 Release** waehlen, warten bis "CMake generation finished"
Output-Fenster: View > Output > Show output from: CMake), dann **Build > Build All**.

**Per Kommandozeile** (Developer PowerShell for VS aus dem Startmenue — dort sind cl.exe,
cmake, ninja im PATH; mit VS Code + CMake-Tools dasselbe Ergebnis):

```powershell
cd C:\dev\kicad
cmake --preset msvc-win64-release
cmake --build --preset win64-release
# Output: build\msvc-win64-release
```

## 6. Starten

Aus dem Build-Ordner braucht KiCad zwei Dinge (siehe `.vs\launch.vs.json` in den Doku-Beispielen):

```powershell
$env:KICAD_RUN_FROM_BUILD_DIR = "1"
$env:PATH = "C:\dev\kicad\build\msvc-win64-release\vcpkg_installed\x64-windows\bin;C:\dev\kicad\build\msvc-win64-release\common;C:\dev\kicad\build\msvc-win64-release\api;C:\dev\kicad\build\msvc-win64-release\common\gal;$env:PATH"
C:\dev\kicad\build\msvc-win64-release\kicad\kicad.exe
```

Oder installierte Variante:

```powershell
cmake --install C:\dev\kicad\build\msvc-win64-release --prefix C:\dev\kicad-install
C:\dev\kicad-install\bin\kicad.exe
```

Im Projektmanager erscheint rechts das Pane **„Project Status"**.

## 7. Hinweise

- Debug-Build analog mit `msvc-win64-debug` / `win64-debug`.
- Presets siehe `CMakePresets.json.sample`: `msvc-win64-release` (RelWithDebInfo, empfohlen),
  `msvc-win64-debug`, arm64-Varianten, linux-*.
- vcpkg.json im Source-Tree enthaelt die komplette Abhaengigkeitsliste (wxWidgets, OCC,
  boost, protobuf, ngspice, wxPython, ...).
- Echter .exe-Installer (NSIS): offizieller CI-Pipeline kicad-win-builder; lokal reicht
  die Installation aus Schritt 6.
