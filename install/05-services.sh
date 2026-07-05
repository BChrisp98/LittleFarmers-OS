#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Dienste installieren ==="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

install -m 0644 \
  "$PROJECT_ROOT/services/zigbee2mqtt.service" \
  /etc/systemd/system/zigbee2mqtt.service

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-wifi-fallback.service" \
  /etc/systemd/system/littlefarmers-wifi-fallback.service

install -m 0755 \
  "$PROJECT_ROOT/scripts/wifi-fallback.sh" \
  /usr/local/bin/littlefarmers-wifi-fallback.sh

install -m 0644 \
  "$PROJECT_ROOT/config/wifi-connect.env" \
  /etc/default/wifi-connect

install -m 0644 \
  "$PROJECT_ROOT/config/zigbee2mqtt.yaml" \
  /opt/zigbee2mqtt/data/configuration.yaml

# Zigbee2MQTT muss seine Konfiguration und Daten verändern können.
chown -R littlefarmers:littlefarmers /opt/zigbee2mqtt

mkdir -p /etc/littlefarmers

install -m 0644 \
  "$PROJECT_ROOT/config/system.conf" \
  /etc/littlefarmers/system.conf

install -m 0755 \
  "$PROJECT_ROOT/scripts/firstboot.sh" \
  /usr/local/bin/littlefarmers-firstboot.sh

install -m 0644 \
  "$PROJECT_ROOT/services/firstboot.service" \
  /etc/systemd/system/firstboot.service


systemctl daemon-reload

systemctl enable NetworkManager.service
systemctl enable avahi-daemon.service
systemctl enable ssh.service
systemctl enable zigbee2mqtt.service
systemctl enable littlefarmers-wifi-fallback.service
systemctl enable firstboot.service

# WiFi Connect darf nicht dauerhaft laufen.
systemctl disable --now wifi-connect.service 2>/dev/null || true

echo "=== Dienste installiert und für Autostart aktiviert ==="