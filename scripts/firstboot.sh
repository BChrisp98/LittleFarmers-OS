#!/usr/bin/env bash
set -euo pipefail

MARKER="/var/lib/littlefarmers/firstboot-complete"

if [[ -f "$MARKER" ]]; then
  exit 0
fi

echo "=== LittleFarmers: Erster Systemstart ==="

mkdir -p /var/lib/littlefarmers

# Eindeutige System-ID erzeugen, falls das Golden Image bereinigt wurde.
if [[ ! -s /etc/machine-id ]]; then
  systemd-machine-id-setup
fi

# Individuelle SSH-Hostschlüssel pro Kundengerät erzeugen.
ssh-keygen -A

# WLAN aktivieren.
rfkill unblock wifi || true
nmcli networking on || true
nmcli radio wifi on || true

touch "$MARKER"

echo "=== First Boot abgeschlossen ==="