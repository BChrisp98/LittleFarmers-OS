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

echo "=== BLE-Provisioning installiert ==="
