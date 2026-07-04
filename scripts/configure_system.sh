#!/usr/bin/env bash
set -euo pipefail

echo "=== System konfigurieren ==="

HOSTNAME_TARGET="littlefarmers"

hostnamectl set-hostname "$HOSTNAME_TARGET"

apt-get update
apt-get install -y \
  curl \
  git \
  ca-certificates \
  build-essential \
  avahi-daemon \
  network-manager \
  dnsmasq-base \
  openssh-server

systemctl enable --now NetworkManager.service
systemctl enable --now avahi-daemon.service
systemctl enable --now ssh.service

systemctl disable --now comitup.service 2>/dev/null || true
systemctl disable --now comitup-web.service 2>/dev/null || true
systemctl disable --now hostapd.service 2>/dev/null || true
systemctl mask hostapd.service 2>/dev/null || true

echo "=== System fertig ==="