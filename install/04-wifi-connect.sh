#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: WiFi Connect installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

VERSION="4.4.6"
ARCH="$(dpkg --print-architecture)"
TMP_DIR="$(mktemp -d)"

case "$ARCH" in
  arm64)
    ASSET_ARCH="aarch64"
    ;;
  armhf)
    ASSET_ARCH="rpi"
    ;;
  *)
    echo "Nicht unterstützte Architektur: $ARCH"
    exit 1
    ;;
esac

apt-get install -y \
  curl \
  ca-certificates \
  network-manager \
  dnsmasq-base

DOWNLOAD_URL="https://github.com/balena-os/wifi-connect/releases/download/v${VERSION}/wifi-connect-v${VERSION}-linux-${ASSET_ARCH}.tar.gz"

cd "$TMP_DIR"

curl -fL "$DOWNLOAD_URL" -o wifi-connect.tar.gz
tar -xzf wifi-connect.tar.gz

install -m 0755 wifi-connect /usr/local/sbin/wifi-connect

/usr/local/sbin/wifi-connect --version

rm -rf "$TMP_DIR"

echo "=== WiFi Connect installiert ==="