#!/usr/bin/env bash
# One-command diagnostic for the WLAN-Fallback/Hotspot setup - built so
# testing doesn't require typing raw grep/diff/nmcli commands by hand off
# a monitor. Run as: sudo ./wifi-test.sh
#
# Prints a plain-language report (deployed script up to date? wlan0 link
# state? NetworkManager's view? actual kernel IP? undervoltage flags?
# recent hotspot log lines?), then optionally triggers one controlled
# hotspot start attempt and watches it live.
set -uo pipefail

REPO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/wifi-fallback.sh"
DEPLOYED_SCRIPT="/usr/local/bin/littlefarmers-wifi-fallback.sh"

line() { printf '%s\n' "----------------------------------------"; }

if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo ausfuehren: sudo ./wifi-test.sh"
  exit 1
fi

line
echo "1) Ist die neueste Fix-Version auf dem Pi installiert?"
line
if [[ ! -f "$DEPLOYED_SCRIPT" ]]; then
  echo "PROBLEM: $DEPLOYED_SCRIPT existiert nicht."
elif diff -q "$REPO_SCRIPT" "$DEPLOYED_SCRIPT" >/dev/null 2>&1; then
  echo "OK: Installierte Version ist identisch mit dem Repo (aktuell)."
else
  echo "PROBLEM: Installierte Version weicht vom Repo ab - installiere sie jetzt neu."
  install -m 0755 "$REPO_SCRIPT" "$DEPLOYED_SCRIPT"
  echo "-> Neu installiert. Dienst wird neu gestartet."
  systemctl restart littlefarmers-wifi-fallback
  sleep 2
fi

line
echo "2) Stromversorgung (vcgencmd get_throttled)"
line
if command -v vcgencmd >/dev/null 2>&1; then
  raw="$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"
  val=$((raw))
  echo "Rohwert: $raw"
  if (( val & 0x1 )); then echo "JETZT: Unterspannung aktiv"; fi
  if (( val & 0x4 )); then echo "JETZT: Drosselung aktiv"; fi
  if (( val & 0x10000 )); then echo "SEIT BOOT: Unterspannung ist mindestens einmal aufgetreten"; fi
  if (( val & 0x40000 )); then echo "SEIT BOOT: Drosselung ist mindestens einmal aufgetreten"; fi
  if (( val == 0 )); then echo "OK: Keine Unterspannung/Drosselung erkannt."; fi
else
  echo "vcgencmd nicht verfuegbar (kein Raspberry Pi Firmware-Tool)."
fi

line
echo "3) wlan0 - Zustand im Kernel"
line
ip -brief link show wlan0 2>&1 || echo "PROBLEM: wlan0 existiert nicht."
ip -4 -brief addr show wlan0 2>&1

line
echo "4) wlan0 - Sicht von NetworkManager"
line
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>&1 | grep -E '^wlan0:' || echo "PROBLEM: NetworkManager kennt wlan0 nicht."

line
echo "5) Letzte 30 Log-Zeilen vom Fallback-Dienst"
line
journalctl -u littlefarmers-wifi-fallback -n 30 --no-pager 2>&1

line
echo "Fertig. Fuer einen kontrollierten Hotspot-Testlauf jetzt:"
echo "  sudo ./wifi-test.sh --start-hotspot"
line

if [[ "${1:-}" == "--start-hotspot" ]]; then
  echo ""
  echo "Setze wlan0 zurueck und starte den Hotspot testweise fuer ~25 Sekunden..."
  echo "(Achtung: laeuft wlan0 gerade als SSH-Weg, bricht die Verbindung ab - das ist normal.)"
  nmcli device set wlan0 managed yes >/dev/null 2>&1 || true
  nmcli device disconnect wlan0 >/dev/null 2>&1 || true
  sleep 1

  source /etc/littlefarmers/system.conf
  TEST_CONN="LittleFarmers-Hotspot-Test"
  nmcli connection delete "$TEST_CONN" >/dev/null 2>&1 || true
  nmcli connection add type wifi ifname wlan0 con-name "$TEST_CONN" ssid "${HOTSPOT_SSID:-LittleFarmers}" >/dev/null 2>&1
  nmcli connection modify "$TEST_CONN" 802-11-wireless.mode ap 802-11-wireless.band bg >/dev/null 2>&1
  nmcli connection modify "$TEST_CONN" ipv4.method shared >/dev/null 2>&1
  if [[ -n "${HOTSPOT_PASSWORD:-}" ]]; then
    nmcli connection modify "$TEST_CONN" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASSWORD" >/dev/null 2>&1
  fi

  if nmcli connection up "$TEST_CONN" >/dev/null 2>&1; then
    echo "ERFOLG: Hotspot-Verbindung aktiviert."
    ip -4 -brief addr show wlan0
  else
    echo "FEHLER: Hotspot-Verbindung konnte nicht aktiviert werden."
  fi

  nmcli connection down "$TEST_CONN" >/dev/null 2>&1 || true
  nmcli connection delete "$TEST_CONN" >/dev/null 2>&1 || true
fi
