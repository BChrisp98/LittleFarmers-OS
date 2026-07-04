#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Basissystem installieren ==="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/config/system.conf"

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

hostnamectl set-hostname "$HOSTNAME"

apt-get update
apt-get install -y \
  curl \
  git \
  ca-certificates \
  build-essential \
  avahi-daemon \
  network-manager \
  dnsmasq-base \
  openssh-server \
  iputils-ping \
  rfkill

systemctl enable NetworkManager.service
systemctl enable avahi-daemon.service
systemctl enable ssh.service

# Andere Hotspot-Systeme dürfen nicht parallel laufen.
systemctl disable --now comitup.service 2>/dev/null || true
systemctl disable --now comitup-web.service 2>/dev/null || true
systemctl disable --now hostapd.service 2>/dev/null || true
systemctl mask hostapd.service 2>/dev/null || true

rfkill unblock wifi || true

echo "=== Basissystem fertig ==="