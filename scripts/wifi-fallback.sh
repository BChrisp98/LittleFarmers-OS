#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/littlefarmers/system.conf"
WIFI_CONNECT_ENV="/etc/default/wifi-connect"
# Eigene Oberflaeche statt wifi-connects mitgelieferter Standard-UI (siehe
# install/04-wifi-connect.sh und wifi-connect-ui/index.html im Repo) - die
# leitet den Kunden nach erfolgreicher Verbindung direkt in die
# LittleFarmers-App weiter, statt dass er den Kopplungscode woanders
# ablesen und von Hand eintippen muss (Christoph, 2026-08-22).
UI_DIRECTORY="/opt/littlefarmers/wifi-connect-ui"
DEVICE_CODE_FILE="/etc/littlefarmers/device-code"

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

prepare_wifi_interface() {
  # Force wlan0 into a clean, known state right before wifi-connect takes
  # over - part of the os-error-99 workaround below (see there for the
  # full story). Cheap insurance against wlan0 still being half-configured
  # from whatever it was doing a moment ago (client mode, a previous
  # failed AP attempt, etc.).
  nmcli device set wlan0 managed yes >/dev/null 2>&1 || true
  nmcli device disconnect wlan0 >/dev/null 2>&1 || true
  ip link set wlan0 down >/dev/null 2>&1 || true
  sleep 2
  ip link set wlan0 up >/dev/null 2>&1 || true
  sleep 2
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

  # HOTSPOT_SSID/HOTSPOT_PASSWORD standen bisher zwar in system.conf, wurden
  # aber nie tatsaechlich an wifi-connect weitergegeben - das Tool lief mit
  # seinen eigenen Standardwerten (offener Hotspot, andere SSID). Jeder in
  # Funkreichweite waehrend der Ersteinrichtung haette sich verbinden koennen.
  # Sicherheitspruefung 2026-08-15 - jetzt tatsaechlich durchgereicht.
  WIFI_CONNECT_ARGS=(--portal-ssid "$HOTSPOT_SSID")
  if [[ -n "${HOTSPOT_PASSWORD:-}" ]]; then
    WIFI_CONNECT_ARGS+=(--portal-passphrase "$HOTSPOT_PASSWORD")
  else
    log_message "WARNUNG: HOTSPOT_PASSWORD ist leer - Einrichtungs-Hotspot laeuft offen (kein Passwort)."
  fi

  if [[ -d "$UI_DIRECTORY" ]]; then
    WIFI_CONNECT_ARGS+=(--ui-directory "$UI_DIRECTORY")
    # Frisch bei jedem Hotspot-Start kopiert (nicht einmalig bei der
    # Installation), damit ein per firstboot.sh nachtraeglich erst
    # erzeugter Code hier garantiert schon drinsteht.
    if [[ -s "$DEVICE_CODE_FILE" ]]; then
      mkdir -p "$UI_DIRECTORY/static"
      cp "$DEVICE_CODE_FILE" "$UI_DIRECTORY/static/pairing-code.txt"
    else
      log_message "WARNUNG: $DEVICE_CODE_FILE fehlt - Weiterleitung zur App nach WLAN-Setup nicht moeglich."
    fi
  else
    log_message "WARNUNG: $UI_DIRECTORY fehlt - wifi-connect laeuft mit seiner eingebauten Standard-Oberflaeche."
  fi

  # wifi-connect has a known race: NetworkManager can report the access
  # point as created a moment before the 192.168.42.1 address is actually
  # bound to wlan0, so wifi-connect's own HTTP server then fails with
  # "Cannot assign requested address" and the whole process exits within
  # ~15 seconds - confirmed live on real hardware, 2026-08-23. Can't fix
  # that race inside wifi-connect itself without patching and recompiling
  # its Rust source (no toolchain available for that here).
  #
  # First attempt at a fix here was a blind retry loop (just re-running
  # wifi-connect a few times) - dropped after a follow-up test showed it
  # losing the SAME race 5 times in a row, back to back, in well under a
  # minute total. That's not occasional bad luck, that's deterministic on
  # this hardware, so retrying the identical sequence doesn't help.
  #
  # This version instead runs wifi-connect in the background and watches
  # it from outside for the first ~20 seconds: if NetworkManager reports
  # wlan0 as active but the portal IP genuinely isn't bound yet in the
  # kernel (checked via `ip addr`, not trusted from nmcli's own state),
  # we assign it ourselves with `ip addr replace` - which is safe to run
  # even if NetworkManager is mid-assignment, unlike `ip addr add`. If
  # wifi-connect still dies fast even with that in place, one retry with
  # a fresh prepare_wifi_interface cleanup; if it dies fast again after
  # that too, this almost certainly isn't the IP-timing race anymore
  # (interface/driver/power problem instead - see the low-voltage warning
  # noted the same day this was found) and retrying further won't help.
  hotspot_attempt=0
  while [[ "$hotspot_attempt" -lt 2 ]]; do
    hotspot_attempt=$((hotspot_attempt + 1))

    prepare_wifi_interface

    if command -v vcgencmd >/dev/null 2>&1; then
      log_message "Spannungsstatus vor Hotspot-Start: $(vcgencmd get_throttled 2>/dev/null || echo unbekannt)"
    fi

    # Measured from here, not from before prepare_wifi_interface - that
    # function alone takes ~4s (two deliberate 2s settle-sleeps), which
    # was silently pushing every attempt's measured duration past the 20s
    # cutoff below even when wifi-connect itself only ran ~15-17s. Bug:
    # the retry branch never actually fired because of this, on both
    # attempts logged 2026-08-23 19:09 and 19:14 - we only ever saw
    # attempt 1 fail, never got real data on whether attempt 2 helps.
    attempt_start="$(date +%s)"

    timeout --signal=TERM "$HOTSPOT_RUNTIME" \
      /usr/local/sbin/wifi-connect "${WIFI_CONNECT_ARGS[@]}" &
    wc_pid=$!

    watchdog_ticks=0
    while [[ "$watchdog_ticks" -lt 80 ]]; do
      if ! kill -0 "$wc_pid" 2>/dev/null; then
        break
      fi
      if ip -4 addr show dev wlan0 2>/dev/null | grep -q '192\.168\.42\.1/'; then
        break
      fi
      if nmcli -t -f GENERAL.STATE device show wlan0 2>/dev/null | grep -q '^100'; then
        ip addr replace 192.168.42.1/24 dev wlan0 >/dev/null 2>&1 || true
      fi
      sleep 0.25
      watchdog_ticks=$((watchdog_ticks + 1))
    done

    wait "$wc_pid" || true

    attempt_duration=$(($(date +%s) - attempt_start))
    if [[ "$attempt_duration" -ge 20 ]]; then
      break
    fi
    log_message "Hotspot endete ungewoehnlich schnell (${attempt_duration}s) trotz IP-Watchdog - versuche einmal erneut (Versuch $hotspot_attempt/2)."
    sleep 2
  done

  log_message "Einrichtungs-Hotspot wurde beendet."

  offline_since=0

  nmcli networking on >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true

  sleep "$CHECK_INTERVAL"
done