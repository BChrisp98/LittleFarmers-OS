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

# Standardwerte, falls sie nicht in der Konfiguration stehen.
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
NO_INTERNET_TIMEOUT="${NO_INTERNET_TIMEOUT:-90}"
HOTSPOT_RUNTIME="${HOTSPOT_RUNTIME:-600}"
CONNECTIVITY_HOST="${CONNECTIVITY_HOST:-1.1.1.1}"
HOTSPOT_SSID="${HOTSPOT_SSID:-LittleFarmers-Setup}"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

internet_available() {
  ping -c 1 -W 3 "$CONNECTIVITY_HOST" >/dev/null 2>&1
}

enable_wifi_autoconnect() {
  while IFS=: read -r connection_uuid connection_type; do
    if [[ "$connection_type" == "802-11-wireless" ]]; then
      nmcli connection modify uuid "$connection_uuid" \
        connection.autoconnect yes \
        connection.autoconnect-retries 0 \
        >/dev/null 2>&1 || true
    fi
  done < <(nmcli -t -f UUID,TYPE connection show)
}

try_saved_wifi_connections() {
  log_message "Versuche gespeicherte WLAN-Verbindungen."

  nmcli networking on >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true

  enable_wifi_autoconnect

  while IFS=: read -r connection_uuid connection_type; do
    if [[ "$connection_type" != "802-11-wireless" ]]; then
      continue
    fi

    log_message "Versuche gespeichertes WLAN-Profil $connection_uuid."

    nmcli --wait 20 connection up uuid "$connection_uuid" \
      >/dev/null 2>&1 || true

    sleep 3

    if internet_available; then
      log_message "Internetverbindung wurde wiederhergestellt."
      return 0
    fi
  done < <(nmcli -t -f UUID,TYPE connection show)

  return 1
}

offline_since=0

log_message "LittleFarmers WLAN-Fallback gestartet."

enable_wifi_autoconnect

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

  if try_saved_wifi_connections; then
    offline_since=0
    sleep "$CHECK_INTERVAL"
    continue
  fi

  log_message "Gespeicherte WLAN-Verbindungen funktionieren nicht."
  log_message "Starte Einrichtungs-Hotspot $HOTSPOT_SSID."

  timeout --signal=TERM "$HOTSPOT_RUNTIME" \
    /usr/local/sbin/wifi-connect || true

  log_message "Einrichtungs-Hotspot wurde beendet."

  offline_since=0

  nmcli networking on >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true

  sleep "$CHECK_INTERVAL"
done