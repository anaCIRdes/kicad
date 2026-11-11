# Anleitung: Patched KiCad in Proxmox-LXC bauen (CT107 "kicadbuilder")

## 1. Container anlegen (Proxmox-GUI)

- Vorlage `debian-13-standard`, Hostname `kicadbuilder`, CTID z. B. **107**
- **Unprivileged** anhaken, On boot: ja
- Speicher: **ZFS-Pool-HDD1** (NICHT ZFS-Pool/QLC), mind. 40 GB rootfs
- Netzwerk: Bridge `vmbr0`, IP z. B. `10.0.0.107/24`, Gateway `10.0.0.1`
- 4 Cores, 8192 MB RAM

## 2. Firewall: SSH (Port 22) erlauben

PVE-Firewall läuft mit Default-Drop. Auf dem Host Regel anlegen
(Datacenter → Firewall oder pro CT → Firewall):
IN / ACCEPT / TCP / Dest. port **22**

## 3. SSH im Container einrichten (als root IM Container, GUI-Console)

```bash
apt-get update
apt-get install -y openssh-server unzip patch
ssh-keygen -A
mkdir -p /run/sshd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
/usr/sbin/sshd
passwd
```
Test: `ss -tlnp | grep :22`

## 4. Paket in den Container kopieren (vom Client-PC)

```bash
scp kicad-status-pane.zip root@10.0.0.107:/home/kicad/
# oder: sftp root@10.0.0.107  →  put kicad-status-pane.zip /home/kicad/
# oder vom Proxmox-Host:  pct push 107 kicad-status-pane.zip /home/kicad/
```

## 5. Bau im Container starten

```bash
ssh root@10.0.0.107
cd /home/kicad
unzip -o kicad-status-pane.zip -d kicad-status-pane
cd kicad-status-pane
bash ct-build-kicad.sh        # root-Rechte reichen, KEIN sudo nötig
```

Wichtige trixie-Fixes sind bereits eingebaut: Dev-Paket heißt **`libngspice0-dev`**
(nicht `libngspice-dev`), CMake braucht **`-DKICAD_USE_SPNAV=OFF`** zusätzlich zu
`-DKICAD_USE_OCC=OFF`, und **wx-config** wird als Wrapper nachinstalliert
(siehe unten). Version auto-erkannt (aktuell **10.0.8**).

**wx-config-Hinweis (trixie):** Debian 13 liefert das `wx-config`-Binary nicht mehr
im Paket, aber das komplette Skript liegt unter
`/usr/lib/x86_64-linux-gnu/wx/config/gtk3-unicode-3.2`. KiCads
`cmake/FindwxWidgets.cmake` braucht zwingend ein `wx-config`, sonst bricht CMake ab
mit `Could NOT find wxWidgets (missing: wxWidgets_LIBRARIES)`. `ct-build-kicad.sh`
ruft deshalb automatisch `wx-config-fix.sh` auf, das `/usr/local/bin/wx-config`
als Wrapper installiert. Manuell geht das so:

```bash
apt-get install -y libwxgtk3.2-dev libwxgtk-webview3.2-dev libwxgtk-media3.2-dev \
    libgtk-3-dev libwebkit2gtk-4.1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
printf '#!/bin/sh\nexec /usr/lib/x86_64-linux-gnu/wx/config/gtk3-unicode-3.2 "$@"\n' \
    > /usr/local/bin/wx-config && chmod +x /usr/local/bin/wx-config
wx-config --version        # -> 3.2.8
```

Falls der Patch mit `git apply` doch meckert, im Container manuell:

```bash
cd /home/kicad/kicad-src
cp ../kicad-status-pane/src/project_status_pane.* kicad/
patch -p1 --fuzz=3 < ../kicad-status-pane/patches/mod.patch
```

Dauer: ca. 1–3 h.

## 6. Ergebnis abholen

```bash
# auf dem Proxmox-Host:
pct pull 107 /home/kicad/kicad-build-out/kicad ./kicad
pct pull 107 /home/kicad/kicad-build-out/kicad-cli ./kicad-cli
```

`proxmox-kicad-lxc.sh` ist OPTIONAL (nur Proxmox-Host, legt CT automatisch an).
