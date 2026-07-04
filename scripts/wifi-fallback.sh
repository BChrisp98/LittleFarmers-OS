#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/littlefarmers/system.conf"
WIFI_CONNECT_ENV="/etc/default/wifi-connect"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Konfiguration fehlt: $CONFIG_FILE"
  exit 1
fi

source "$CONFIG_FILE"

if [[ -f "$WIFI_CONNECT_ENV" ]]; then
  set -a
  source "$WIFI_CONNECT_ENV"
  set +a
fi

internet_available() {
  ping -c 1 -W 3 "$CONNECTIVITY_HOST" >/dev/null 2>&1
}

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

offline_since=0

log_message "LittleFarmers WLAN-Fallback gestartet."

while true; do
  if internet_available; then
    offline_since=0
    sleep "$CHECK_INTERVAL"
    continue
  fi

  current_time="$(date +%s)"

  if [[ "$offline_since" -eq 0 ]]; then
    offline_since="$current_time"
    log_message "Keine Internetverbindung erkannt."
  fi

  offline_duration=$((current_time - offline_since))

  if [[ "$offline_duration" -lt "$NO_INTERNET_TIMEOUT" ]]; then
    sleep "$CHECK_INTERVAL"
    continue
  fi

  log_message "Starte Hotspot $HOTSPOT_SSID."

  timeout --signal=TERM "$HOTSPOT_RUNTIME" \
    /usr/local/sbin/wifi-connect || true

  log_message "Hotspot beendet. Bekannte WLAN-Verbindungen werden erneut versucht."

  offline_since=0
  nmcli networking on >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true

  sleep "$CHECK_INTERVAL"
done