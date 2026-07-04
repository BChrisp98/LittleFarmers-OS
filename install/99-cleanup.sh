#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Aufräumen ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

apt-get autoremove -y
apt-get clean

rm -rf /tmp/wifi-connect* 2>/dev/null || true

echo "=== Aufräumen abgeschlossen ==="