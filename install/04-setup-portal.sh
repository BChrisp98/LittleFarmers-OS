#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Setup-Portal installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

# Ersetzt seit 2026-08-23 balena-os/wifi-connect komplett (siehe
# scripts/wifi-fallback.sh fuer die volle Begruendung: wifi-connect hatte
# ein reproduzierbares internes Race zwischen AP-Erstellung und eigenem
# HTTP-Server-Bind, das auf echter Hardware zuverlaessig fehlschlug).
# NetworkManager erledigt die AP-Erstellung jetzt direkt per nmcli,
# dieser kleine Python-Server (wifi-connect-ui/portal_server.py) liefert
# nur noch die Einrichtungsseite aus und reicht WLAN-Verbindungswuensche
# an nmcli weiter. Kein separates Zusatzpaket mehr noetig ausser Python
# selbst, das ohnehin fuer Zigbee2MQTT/das restliche System vorausgesetzt
# wird.
apt-get install -y \
  network-manager \
  python3

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p /opt/littlefarmers/wifi-connect-ui
cp -r "$PROJECT_ROOT/wifi-connect-ui/." /opt/littlefarmers/wifi-connect-ui/
chown -R littlefarmers:littlefarmers /opt/littlefarmers/wifi-connect-ui

echo "=== Setup-Portal installiert ==="
