#!/usr/bin/env bash
set -euo pipefail

# Pi-Onboarding Option A (siehe docs/ONBOARDING-PLAN.md, docs/BROKER-
# SECURITY-PLAN.md): dieses Skript ist die Geraete-Seite des dort
# beschriebenen Ablaufs. WLAN-Einrichtung (wifi-fallback.sh)
# bleibt komplett unangetastet - dieses Skript startet danach, sobald
# echtes Internet da ist, und tut nur eins: den eigenen Kopplungscode an
# das Backend melden, warten bis der Kunde ihn in der App eingegeben hat,
# und danach Zigbee2MQTT mit den vom Backend gelieferten Zugangsdaten neu
# konfigurieren.
#
# Kein JSON-Parser noetig (kein python3 auf dem Golden Image an dieser
# Stelle installiert, Node.js ist erst nach install/02-node.sh da) - die
# Backend-Antworten sind bewusst flach und ohne verschachtelte Werte
# gehalten, daher reicht grep/sed, im selben Stil wie wifi-fallback.sh
# schon nmcli-Ausgaben parst.

CONFIG_FILE="/etc/littlefarmers/system.conf"
STATE_DIR="/var/lib/littlefarmers"
CODE_FILE="/etc/littlefarmers/device-code"
MARKER="$STATE_DIR/paired"
ZIGBEE_CONFIG="/opt/zigbee2mqtt/data/configuration.yaml"

if [[ -f "$MARKER" ]]; then
  echo "Geraet ist bereits gekoppelt (siehe $MARKER) - nichts zu tun."
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Konfiguration fehlt: $CONFIG_FILE"
  exit 1
fi
source "$CONFIG_FILE"

BACKEND_URL="${BACKEND_URL:-http://18.159.76.112:8000}"
PAIR_POLL_INTERVAL="${PAIR_POLL_INTERVAL:-5}"

log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

mkdir -p "$STATE_DIR" /etc/littlefarmers

# Der Kopplungscode wird einmalig aus der (ab Werk pro Geraet
# einzigartigen, siehe firstboot.sh) machine-id abgeleitet und dauerhaft
# abgelegt - das ist der Code, der als Aufkleber/QR-Code auf das Geraet
# kommt (Produktions-/Logistikthema, siehe ONBOARDING-PLAN.md, hier nur
# vorbereitet: `cat /etc/littlefarmers/device-code` liefert ihn).
if [[ ! -s "$CODE_FILE" ]]; then
  if [[ ! -s /etc/machine-id ]]; then
    log_message "machine-id fehlt - kann keinen Kopplungscode erzeugen."
    exit 1
  fi
  sha256sum /etc/machine-id | cut -c1-12 > "$CODE_FILE"
fi
DEVICE_CODE="$(cat "$CODE_FILE")"
log_message "Kopplungscode dieses Geraets: $DEVICE_CODE"

internet_available() {
  ping -c 1 -W 3 "${CONNECTIVITY_HOST:-1.1.1.1}" >/dev/null 2>&1
}

log_message "Warte auf Internetverbindung, bevor die Kopplung beginnt."
until internet_available; do
  sleep "$PAIR_POLL_INTERVAL"
done

log_message "Starte Kopplung - warte bis das Geraet in der App zugeordnet wird."
while true; do
  response="$(curl -fsS "$BACKEND_URL/api/devices/$DEVICE_CODE/status" 2>/dev/null || true)"

  if [[ -z "$response" ]]; then
    sleep "$PAIR_POLL_INTERVAL"
    continue
  fi

  if [[ "$response" != *'"ready": true'* && "$response" != *'"ready":true'* ]]; then
    if [[ "$response" == *'"claimed": true'* || "$response" == *'"claimed":true'* ]]; then
      log_message "Geraet ist einem Konto zugeordnet, warte noch auf Broker-Zugangsdaten."
    fi
    sleep "$PAIR_POLL_INTERVAL"
    continue
  fi

  extract_field() {
    echo "$response" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/.*:[[:space:]]*\"(.*)\"/\1/"
  }
  extract_number() {
    echo "$response" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9]*" | grep -o '[0-9]*$'
  }

  mqtt_host="$(extract_field mqttHost)"
  mqtt_port="$(extract_number mqttPort)"
  mqtt_username="$(extract_field mqttUsername)"
  mqtt_password="$(extract_field mqttPassword)"
  mqtt_base_topic="$(extract_field mqttBaseTopic)"

  if [[ -z "$mqtt_host" ]]; then
    log_message "Antwort ohne mqttHost - überspringe diese Runde."
    sleep "$PAIR_POLL_INTERVAL"
    continue
  fi
  mqtt_port="${mqtt_port:-1883}"

  log_message "Zugangsdaten erhalten - schreibe Zigbee2MQTT-Konfiguration neu (Broker: $mqtt_host:$mqtt_port, Namensraum: ${mqtt_base_topic:-zigbee2mqtt})."

  cp "$ZIGBEE_CONFIG" "$ZIGBEE_CONFIG.bak"
  sed -i \
    -e "s|^\(\s*server:\).*|\1 mqtt://$mqtt_host:$mqtt_port|" \
    -e "s|^\(\s*base_topic:\).*|\1 ${mqtt_base_topic:-zigbee2mqtt}|" \
    "$ZIGBEE_CONFIG"
  # user/password sind in einer frischen Zigbee2MQTT-Konfiguration noch
  # nicht vorhanden (siehe config/zigbee2mqtt.yaml) - beim ersten Koppeln
  # unter der server-Zeile neu einfuegen statt versuchen sie zu ersetzen.
  if [[ -n "$mqtt_username" ]] && ! grep -q "^\s*user:" "$ZIGBEE_CONFIG"; then
    sed -i "/^\s*server:/a\\  user: $mqtt_username\\n  password: $mqtt_password" "$ZIGBEE_CONFIG"
  fi

  sed -i \
    -e "s|^MQTT_SERVER=.*|MQTT_SERVER=\"mqtt://$mqtt_host:$mqtt_port\"|" \
    -e "s|^MQTT_BASE_TOPIC=.*|MQTT_BASE_TOPIC=\"${mqtt_base_topic:-zigbee2mqtt}\"|" \
    "$CONFIG_FILE"

  systemctl restart zigbee2mqtt.service

  touch "$MARKER"
  log_message "Kopplung abgeschlossen, Zigbee2MQTT neu gestartet."
  exit 0
done
