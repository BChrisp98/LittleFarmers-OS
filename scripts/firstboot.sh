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

# Zufaelliges, einzigartiges Systempasswort pro Geraet setzen - ohne das
# haetten alle aus demselben Golden Image geklonten Kundengeraete dasselbe
# (beim einmaligen Erstellen des Golden Image gesetzte) Passwort, und wer
# es kennt, kaeme per SSH auf JEDES Kundengeraet. Sicherheitspruefung
# 2026-08-15. Landet nur lokal, root-lesbar, auf diesem einen Geraet - fuer
# den seltenen Support-Fall reicht physischer Zugriff (Monitor/Tastatur)
# vor Ort, kein geteiltes Passwort uebers Netz.
SYSTEM_USER="littlefarmers"
if id "$SYSTEM_USER" &>/dev/null; then
  NEW_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
  echo "${SYSTEM_USER}:${NEW_PASSWORD}" | chpasswd
  echo "$NEW_PASSWORD" > /var/lib/littlefarmers/initial-password
  chmod 0600 /var/lib/littlefarmers/initial-password
fi

# WLAN aktivieren.
rfkill unblock wifi || true
nmcli networking on || true
nmcli radio wifi on || true

touch "$MARKER"

echo "=== First Boot abgeschlossen ==="