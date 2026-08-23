#!/usr/bin/env bash
set -uo pipefail

# Runs weekly (see services/littlefarmers-update.timer) so a device
# already out in the field keeps getting fixes automatically, not just
# once on its very first boot (see self-update-firstboot.sh for that
# one-shot case). Christoph, 2026-08-23: once a month wouldn't be often
# enough - weekly.
#
# `set -e` deliberately NOT used, same reasoning as
# self-update-firstboot.sh: a git/network hiccup on one scheduled run
# must not be treated as a service failure - systemd would otherwise
# show a permanently "failed" unit for something that's expected to just
# succeed again next week.

REPO_DIR="/home/littlefarmers/LittleFarmers-OS"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "=== Kein LittleFarmers-OS-Repo unter $REPO_DIR gefunden - woechentliches Update uebersprungen ==="
  exit 0
fi

echo "=== LittleFarmers: Woechentliches Update vom GitHub-Repo ==="

if sudo -u littlefarmers bash -c "cd '$REPO_DIR' && ./update.sh"; then
  echo "=== Woechentliches Update erfolgreich ==="
else
  echo "=== Woechentliches Update fehlgeschlagen (z.B. kein Internet) - naechster Versuch in einer Woche ==="
fi
