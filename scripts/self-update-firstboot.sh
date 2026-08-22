#!/usr/bin/env bash
set -uo pipefail

# Runs once, the first time a freshly-flashed device actually has internet
# (see services/littlefarmers-self-update.service - After=network-online.target,
# unlike firstboot.service which only waits for NetworkManager to be running,
# not for a real connection). Pulls whatever is currently on GitHub and
# re-runs the install scripts, so a device flashed from an old Golden Image
# still ends up on today's code on its very first boot - no manual "ssh in
# and run update.sh" step needed (Christoph, 2026-08-22: "dass du das
# gleich an dem goldenen Image einbaust").
#
# Does NOT retroactively help a device that was flashed BEFORE this script
# existed - it has to already be present (and enabled) in whatever image
# was written to the SD card. It only helps every Golden Image captured
# from here on.
#
# `set -e` deliberately NOT used here (unlike firstboot.sh/update.sh): a
# git/network hiccup on this one boot must never brick startup by leaving
# zigbee2mqtt/pairing waiting on a service that exited non-zero. Every
# step is checked and logged explicitly instead; the marker only gets
# written on full success, so a failed attempt is retried on the next boot.

MARKER="/var/lib/littlefarmers/self-update-complete"
REPO_DIR="/home/littlefarmers/LittleFarmers-OS"

if [[ -f "$MARKER" ]]; then
  exit 0
fi

echo "=== LittleFarmers: Einmaliges Self-Update vom GitHub-Repo ==="

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "=== Kein LittleFarmers-OS-Repo unter $REPO_DIR gefunden - Self-Update übersprungen ==="
  exit 0
fi

if sudo -u littlefarmers bash -c "cd '$REPO_DIR' && ./update.sh"; then
  mkdir -p /var/lib/littlefarmers
  touch "$MARKER"
  echo "=== Self-Update erfolgreich - Gerät ist auf dem aktuellen GitHub-Stand ==="
else
  echo "=== Self-Update fehlgeschlagen (z.B. kein Internet) - startet mit dem Stand des Golden Image, wird beim naechsten Boot erneut versucht ==="
fi
