#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Node.js installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

apt-get install -y curl ca-certificates

curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -

apt-get install -y \
  nodejs \
  git \
  make \
  gcc \
  g++ \
  libsystemd-dev

corepack enable
corepack prepare pnpm@latest --activate

echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "pnpm: $(pnpm --version)"

echo "=== Node.js fertig ==="