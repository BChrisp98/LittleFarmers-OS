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
  nmcli device set wlan0 managed yes >/dev/null 2>&1 || true
  nmcli device disconnect wlan0 >/dev/null 2>&1 || true
  ip link set wlan0 down >/dev/null 2>&1 || true
  sleep 2
  ip link set wlan0 up >/dev/null 2>&1 || true
  sleep 2

  source /etc/littlefarmers/system.conf
  ARGS=(--portal-ssid "${HOTSPOT_SSID:-LittleFarmers}")
  [[ -n "${HOTSPOT_PASSWORD:-}" ]] && ARGS+=(--portal-passphrase "$HOTSPOT_PASSWORD")

  timeout 30 /usr/local/sbin/wifi-connect "${ARGS[@]}" &
  wc_pid=$!

  success=0
  for i in $(seq 1 25); do
    if ! kill -0 "$wc_pid" 2>/dev/null; then
      break
    fi
    if ip -4 addr show dev wlan0 2>/dev/null | grep -q '192\.168\.42\.1/'; then
      success=1
      echo "ERFOLG nach ${i}s: 192.168.42.1 ist aktiv, Hotspot laeuft."
      break
    fi
    sleep 1
  done

  if [[ "$success" -eq 0 ]]; then
    echo "Nach 25s immer noch keine 192.168.42.1 - Hotspot ist NICHT stabil hochgekommen."
  fi

  kill "$wc_pid" >/dev/null 2>&1 || true
  wait "$wc_pid" 2>/dev/null || true
  nmcli connection delete "${HOTSPOT_SSID:-LittleFarmers}" >/dev/null 2>&1 || true
fi
