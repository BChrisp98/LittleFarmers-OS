#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo " LittleFarmers OS Installation"
echo "========================================"

if [[ $EUID -eq 0 ]]; then
  echo "Bitte ohne sudo starten:"
  echo "./install.sh"
  exit 1
fi

sudo -v

sudo bash "$PROJECT_ROOT/install/01-system.sh"
sudo bash "$PROJECT_ROOT/install/02-node.sh"
sudo bash "$PROJECT_ROOT/install/03-zigbee2mqtt.sh"
sudo bash "$PROJECT_ROOT/install/04-setup-portal.sh"
sudo bash "$PROJECT_ROOT/install/05-services.sh"
sudo bash "$PROJECT_ROOT/install/99-cleanup.sh"

echo
echo "========================================"
echo " Installation abgeschlossen"
echo "========================================"
echo
echo "Bitte den Raspberry Pi neu starten:"
echo "sudo reboot"