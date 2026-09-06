#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Zigbee2MQTT installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

INSTALL_DIR="/opt/zigbee2mqtt"
SERVICE_USER="${SUDO_USER:-littlefarmers}"

# Pinned, not "whatever upstream master currently is" - critical fix found
# live 2026-09-06: this used to `git pull` master unconditionally on every
# run, including the weekly unattended auto-update
# (littlefarmers-update.timer). A version jump that way (zigbee-herdsman
# 10.8.0 -> 10.9.2 among other changes) hit a real upstream check -
# "Configuration is not consistent with adapter state/backup!" - that
# refuses to start rather than silently reconfigure the network, because
# doing so would force re-pairing every device. Recoverable by hand (see
# git history/commit message for the exact commands), but a real customer
# hit by this via an unattended weekly update would have no one there to
# run them - their device would just crash-loop forever. Bumping this pin
# is now a deliberate, tested decision on our side, not something upstream
# does to us automatically.
ZIGBEE2MQTT_VERSION="2.14.1"

apt-get install -y git

if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$ZIGBEE2MQTT_VERSION" https://github.com/Koenkk/zigbee2mqtt.git "$INSTALL_DIR"
else
  git -C "$INSTALL_DIR" fetch --depth 1 origin "refs/tags/$ZIGBEE2MQTT_VERSION:refs/tags/$ZIGBEE2MQTT_VERSION"
  git -C "$INSTALL_DIR" checkout "$ZIGBEE2MQTT_VERSION"
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