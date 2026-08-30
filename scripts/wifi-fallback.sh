#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/littlefarmers/system.conf"
# Eigene Oberflaeche statt einer mitgelieferten Standard-UI (siehe
# install/04-setup-portal.sh, wifi-connect-ui/index.html und
# wifi-connect-ui/portal_server.py im Repo) - die leitet den Kunden nach
# erfolgreicher Verbindung direkt in die LittleFarmers-App weiter, statt
# dass er den Kopplungscode woanders ablesen und von Hand eintippen muss
# (Christoph, 2026-08-22).
UI_DIRECTORY="/opt/littlefarmers/wifi-connect-ui"
DEVICE_CODE_FILE="/etc/littlefarmers/device-code"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Konfiguration fehlt: $CONFIG_FILE"
  exit 1
fi

source "$CONFIG_FILE"

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
  # Force wlan0 into a clean, known state right before setting up the
  # hotspot connection below. Cheap insurance against wlan0 still being
  # half-configured from whatever it was doing a moment ago (client mode,
  # a previous failed AP attempt, etc.).
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

    # `--wait 20` only bounds how long the nmcli *command* blocks - if the
    # attempt is still going in NetworkManager's backend past that (e.g.
    # DHCP has its own ~45s timeout, confirmed live 2026-08-30), a failed
    # attempt could still be mid-authentication when we move on to either
    # the next saved profile or straight into setting up the hotspot.
    # Explicitly disconnecting here aborts it instead of leaving it to
    # potentially collide with what comes next - suspected cause of the
    # "802.1X supplicant took too long to authenticate" hotspot failures
    # seen the same day.
    nmcli device disconnect wlan0 >/dev/null 2>&1 || true
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
  if [[ -z "${HOTSPOT_PASSWORD:-}" ]]; then
    log_message "WARNUNG: HOTSPOT_PASSWORD ist leer - Einrichtungs-Hotspot laeuft offen (kein Passwort)."
  fi

  # balena-os/wifi-connect replaced entirely (2026-08-23) - real-hardware
  # testing found a reliable internal race: it creates the NetworkManager
  # access point and, in essentially the same instant, tries to bind its
  # own HTTP server to it, and consistently lost that race on this Pi
  # (confirmed repeatedly, including with a from-outside watchdog trying
  # to force the IP - didn't help, the race is inside wifi-connect's own
  # process and too fast to intervene in from outside). The same day, a
  # manual test proved plain `nmcli` (802-11-wireless.mode ap +
  # ipv4.method shared) brings the AP up fast and reliably on this exact
  # hardware, with NetworkManager's own built-in DHCP/DNS - no separate
  # dnsmasq process, which was itself failing ("unknown interface wlan0")
  # every time wifi-connect's bind failed. This does that instead, plus a
  # small stdlib-only Python server (wifi-connect-ui/portal_server.py)
  # that serves the same setup page and turns it into `nmcli` calls.
  HOTSPOT_CONNECTION_NAME="LittleFarmers-Hotspot"

  prepare_wifi_interface

  nmcli connection delete "$HOTSPOT_CONNECTION_NAME" >/dev/null 2>&1 || true

  nmcli connection add type wifi ifname wlan0 con-name "$HOTSPOT_CONNECTION_NAME" ssid "$HOTSPOT_SSID" >/dev/null 2>&1
  nmcli connection modify "$HOTSPOT_CONNECTION_NAME" 802-11-wireless.mode ap 802-11-wireless.band bg >/dev/null 2>&1
  nmcli connection modify "$HOTSPOT_CONNECTION_NAME" ipv4.method shared >/dev/null 2>&1
  if [[ -n "${HOTSPOT_PASSWORD:-}" ]]; then
    nmcli connection modify "$HOTSPOT_CONNECTION_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASSWORD" >/dev/null 2>&1
  fi

  if command -v vcgencmd >/dev/null 2>&1; then
    log_message "Spannungsstatus vor Hotspot-Start: $(vcgencmd get_throttled 2>/dev/null || echo unbekannt)"
  fi

  # Capture nmcli's actual error text and a bit of interface state instead
  # of just logging "failed" with no reason - found live on 2026-08-30
  # that this was failing continuously in the field for potentially a
  # full week with zero diagnostic detail beyond "konnte nicht aktiviert
  # werden", which made it impossible to tell apart from every other
  # possible cause (undervoltage, rfkill, driver not settled yet after
  # prepare_wifi_interface's down/up cycle, etc.).
  if up_output="$(nmcli connection up "$HOTSPOT_CONNECTION_NAME" 2>&1)"; then
    log_message "Hotspot $HOTSPOT_SSID aktiv."

    if [[ -d "$UI_DIRECTORY" ]]; then
      # Frisch bei jedem Hotspot-Start kopiert (nicht einmalig bei der
      # Installation), damit ein per firstboot.sh nachtraeglich erst
      # erzeugter Code hier garantiert schon drinsteht.
      if [[ -s "$DEVICE_CODE_FILE" ]]; then
        mkdir -p "$UI_DIRECTORY/static"
        cp "$DEVICE_CODE_FILE" "$UI_DIRECTORY/static/pairing-code.txt"
      else
        log_message "WARNUNG: $DEVICE_CODE_FILE fehlt - Weiterleitung zur App nach WLAN-Setup nicht moeglich."
      fi

      timeout --signal=TERM "$HOTSPOT_RUNTIME" \
        python3 "$UI_DIRECTORY/portal_server.py" --port "${CAPTIVE_PORT:-80}" --ui-dir "$UI_DIRECTORY" || true
    else
      log_message "FEHLER: $UI_DIRECTORY fehlt - kein Portal-Server, Hotspot laeuft ohne Einrichtungsseite."
      sleep "$HOTSPOT_RUNTIME"
    fi
  else
    log_message "FEHLER: Hotspot-Verbindung konnte nicht aktiviert werden: $up_output"
    log_message "Diagnose - wlan0: $(nmcli -t -f DEVICE,STATE,CONNECTION device status 2>&1 | grep '^wlan0:' || echo 'nicht in nmcli device status gefunden')"
    log_message "Diagnose - rfkill: $(rfkill list wifi 2>&1 | tr '\n' ' ')"
  fi

  nmcli connection down "$HOTSPOT_CONNECTION_NAME" >/dev/null 2>&1 || true
  nmcli connection delete "$HOTSPOT_CONNECTION_NAME" >/dev/null 2>&1 || true

  log_message "Einrichtungs-Hotspot wurde beendet."

  offline_since=0

  nmcli networking on >/dev/null 2>&1 || true
  nmcli radio wifi on >/dev/null 2>&1 || true

  sleep "$CHECK_INTERVAL"
done