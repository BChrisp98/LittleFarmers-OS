#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: WiFi Connect installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

# 4.4.6 (the version this pinned for a long time) fails against newer
# NetworkManager releases - "Error: Getting access points failed / D-Bus
# failure: ...RsnFlags property failed: wrong property type" every time
# the hotspot tries to list nearby networks, so a customer's device could
# never actually show the WLAN-Auswahl during first setup (Christoph, hit
# live on real hardware 2026-08-22). Confirmed fixed on 4.11.84 - see
# https://github.com/balena-os/wifi-connect/issues/416. Note the release
# asset naming changed too (Rust target triples now, no more "-v<ver>-
# linux-<arch>" scheme), which is why ASSET_ARCH/DOWNLOAD_URL below don't
# look like a simple version-number bump.
VERSION="4.11.84"
ARCH="$(dpkg --print-architecture)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

case "$ARCH" in
  arm64)
    ASSET_ARCH="aarch64-unknown-linux-gnu"
    ;;
  armhf)
    ASSET_ARCH="armv7-unknown-linux-gnueabihf"
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

DOWNLOAD_URL="https://github.com/balena-os/wifi-connect/releases/download/v${VERSION}/wifi-connect-${ASSET_ARCH}.tar.gz"

cd "$TMP_DIR"

curl -fL "$DOWNLOAD_URL" -o wifi-connect.tar.gz
tar -xzf wifi-connect.tar.gz

install -m 0755 wifi-connect /usr/local/sbin/wifi-connect

/usr/local/sbin/wifi-connect --version


echo "=== WiFi Connect installiert ==="