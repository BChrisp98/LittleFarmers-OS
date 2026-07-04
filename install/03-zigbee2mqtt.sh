#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Zigbee2MQTT installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

INSTALL_DIR="/opt/zigbee2mqtt"
SERVICE_USER="${SUDO_USER:-littlefarmers}"

apt-get install -y git

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 https://github.com/Koenkk/zigbee2mqtt.git "$INSTALL_DIR"
else
  git -C "$INSTALL_DIR" pull --ff-only
fi

chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"

sudo -u "$SERVICE_USER" bash -c "
  cd '$INSTALL_DIR'
  pnpm install --frozen-lockfile
"

mkdir -p "$INSTALL_DIR/data"
chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/data"

usermod -aG dialout "$SERVICE_USER"

echo "=== Zigbee2MQTT installiert ==="