#!/usr/bin/env bash
# Debian 13 "trixie" ships NO /usr/bin/wx-config anymore (only the man page).
# KiCad's cmake/FindwxWidgets.cmake REQUIRES a wx-config binary, otherwise:
#   "Could NOT find wxWidgets (missing: wxWidgets_LIBRARIES)"
# But libwxgtk3.2-dev contains the full wx-config script at
#   /usr/lib/<triplet>/wx/config/gtk3-unicode-3.2
# This script installs a tiny wrapper as /usr/local/bin/wx-config (idempotent).
# Run as root:  bash wx-config-fix.sh
set -euo pipefail

if command -v wx-config >/dev/null 2>&1; then
    echo ">>> wx-config already present: $(command -v wx-config) ($(wx-config --version 2>/dev/null || echo '?'))"
    exit 0
fi

TRIPLET="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"
REAL=""
for d in "/usr/lib/$TRIPLET/wx/config" /usr/lib/*/wx/config /usr/lib/wx/config; do
    for f in "$d"/gtk3-unicode-3.2 "$d"/gtk3-unicode-*; do
        if [ -f "$f" ] && [ -x "$f" ]; then REAL="$f"; break 2; fi
    done
done

if [ -z "$REAL" ]; then
    echo "ERROR: no wx config script found under /usr/lib/*/wx/config." >&2
    echo "       Install libwxgtk3.2-dev first (apt-get install -y libwxgtk3.2-dev)." >&2
    exit 1
fi

mkdir -p /usr/local/bin
cat > /usr/local/bin/wx-config <<EOF
#!/bin/sh
# wx-config wrapper for Debian trixie (wx-config binary was dropped from the packages)
exec "$REAL" "\$@"
EOF
chmod +x /usr/local/bin/wx-config

echo ">>> installed /usr/local/bin/wx-config -> $REAL"
echo ">>> wx-config --version: $(wx-config --version)"
echo ">>> wx-config --selected-config: $(wx-config --selected-config)"
echo ">>> wx-config --libs core,base: $(wx-config --libs core,base | head -c 200) ..."
