#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Shelly-Unterstuetzung (lokaler Broker + Bridge) ==="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

if ! command -v mosquitto >/dev/null 2>&1 || ! command -v mosquitto_pub >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y mosquitto mosquitto-clients
fi

install -D -m 0644 "$PROJECT_ROOT/config/mosquitto-local.conf" /etc/mosquitto/conf.d/littlefarmers-local.conf
install -m 0755 "$PROJECT_ROOT/scripts/setup-shelly-bridge.sh" /usr/local/bin/littlefarmers-shelly-bridge.sh
install -m 0755 "$PROJECT_ROOT/scripts/announce-address.sh" /usr/local/bin/littlefarmers-announce-address.sh
install -m 0644 "$PROJECT_ROOT/services/littlefarmers-announce.service" /etc/systemd/system/littlefarmers-announce.service

systemctl daemon-reload
systemctl enable mosquitto.service littlefarmers-announce.service
systemctl restart mosquitto.service
# --no-block wie bei den anderen Diensten: darf das Self-Update im ersten Start nicht aufhalten.
systemctl restart --no-block littlefarmers-announce.service

# Schon gekoppelte Geraete bekommen die Bridge beim Update; ungekoppelte beim Koppeln.
/usr/local/bin/littlefarmers-shelly-bridge.sh || true
