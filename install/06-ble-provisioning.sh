#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: BLE-Provisioning installieren ==="

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

# bluez: the Linux Bluetooth stack itself (bluetoothd).
# python3-dbus / python3-gi: bluezero talks to BlueZ over D-Bus, needs
# both the D-Bus bindings and GLib bindings (for the mainloop that
# bluezero's peripheral.publish() runs).
apt-get install -y \
  bluez \
  python3-dbus \
  python3-gi \
  python3-pip

# bluezero itself isn't packaged for apt on Raspberry Pi OS - installed via
# pip. --break-system-packages is needed on Debian Trixie's Python (PEP 668
# externally-managed-environment guard); acceptable here since this is a
# single-purpose appliance image, not a general-purpose dev machine where
# that guard is protecting against real conflicts.
pip3 install --break-system-packages --quiet bluezero

# BlueZ's GATT peripheral/advertising support (exactly what
# ble_provisioning.py needs) lives behind its "--experimental" D-Bus flag -
# without this, bluezero's Peripheral.publish() fails outright. Confirmed
# via BlueZ documentation/community reports 2026-08-30. Drop-in override
# instead of editing the shipped unit file directly, so this survives a
# bluez package update. Read the real ExecStart out of the current unit
# first rather than hardcoding a path - a wrong hardcoded binary path here
# would silently break Bluetooth entirely, which would be a much worse
# regression than the thing this is trying to fix.
#
# Bug found live 2026-09-06: `systemctl show -p ExecStart --value` does NOT
# print a plain path - it prints systemd's own structured exec descriptor,
# e.g. `{ path=/usr/lib/bluetooth/bluetoothd ; argv[]=... ; ... }`. The
# original version here grabbed the first whitespace-delimited token of
# THAT, which is just the opening brace `{` - result: bluetooth.service's
# ExecStart became `{ --experimental`, and it crash-looped
# (status=203/EXEC, "Unable to locate executable '{'") until manually
# undone. Fixed to pull the actual `path=...` field out of that structure,
# and to verify the result is really an executable file before writing
# anything - if either check fails, this warns and skips the override
# instead of guessing.
BLUETOOTHD_EXEC="$(systemctl show bluetooth.service -p ExecStart --value | grep -oE 'path=[^ ;]+' | head -n1 | cut -d= -f2-)"
if [[ -z "$BLUETOOTHD_EXEC" || ! -x "$BLUETOOTHD_EXEC" ]]; then
  echo "WARNUNG: Konnte den bluetoothd-Pfad nicht sicher ermitteln (bekommen: '${BLUETOOTHD_EXEC:-leer}') - --experimental-Override wird uebersprungen."
else
  mkdir -p /etc/systemd/system/bluetooth.service.d
  cat > /etc/systemd/system/bluetooth.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=$BLUETOOTHD_EXEC --experimental
EOF
  systemctl daemon-reload
  systemctl restart bluetooth.service
fi

echo "=== BLE-Provisioning installiert ==="
