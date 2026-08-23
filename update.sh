#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== LittleFarmers OS Update ==="

git -C "$PROJECT_ROOT" pull --ff-only

sudo bash "$PROJECT_ROOT/install/03-zigbee2mqtt.sh"
sudo bash "$PROJECT_ROOT/install/04-setup-portal.sh"
sudo bash "$PROJECT_ROOT/install/05-services.sh"

sudo systemctl restart zigbee2mqtt.service
sudo systemctl restart littlefarmers-wifi-fallback.service

echo "=== Update abgeschlossen ==="