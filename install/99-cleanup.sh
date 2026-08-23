#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Aufräumen ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

apt-get autoremove -y
apt-get clean

# Reste der frueheren wifi-connect-Installation (seit 2026-08-23 durch
# ein eigenes, nmcli-basiertes Setup-Portal ersetzt, siehe
# install/04-setup-portal.sh) - falls das Binary auf diesem Geraet noch
# von einer aelteren Installation vorhanden ist.
rm -f /usr/local/sbin/wifi-connect
rm -f /etc/default/wifi-connect

echo "=== Aufräumen abgeschlossen ==="