#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== LittleFarmers OS Update ==="

git -C "$PROJECT_ROOT" pull --ff-only

sudo bash "$PROJECT_ROOT/install/03-zigbee2mqtt.sh"
sudo bash "$PROJECT_ROOT/install/04-setup-portal.sh"
sudo bash "$PROJECT_ROOT/install/06-ble-provisioning.sh"
sudo bash "$PROJECT_ROOT/install/05-services.sh"

# --no-block: Beim Self-Update im ersten Start (Before=zigbee2mqtt) wuerde ein
# normales "restart" auf das Ende des Self-Updates warten, waehrend dieses auf
# den Neustart wartet - 10 Minuten Stillstand bis zum Timeout (live 2026-10-25).
sudo systemctl restart --no-block zigbee2mqtt.service
sudo systemctl restart --no-block littlefarmers-ble-provisioning.service

echo "=== Update abgeschlossen ==="