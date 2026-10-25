#!/usr/bin/env bash
set -euo pipefail

# Shelly-Unterstuetzung (siehe PLAN-SHELLY-PC.md): Die Shelly im Heimnetz
# sprechen mit dem lokalen Mosquitto dieses Geraets (Port 1883, nur LAN). Eine
# Bridge reicht ALLES Lokale verschluesselt unter <Namensraum>/shelly/ an
# unseren Server weiter (und Befehle von dort zurueck). Gen1-Shelly koennen
# weder TLS noch ihr Themen-Praefix aendern - genau dafuer ist dieser Umweg da.
#
# Die Zugangsdaten stammen aus der Zigbee2MQTT-Konfiguration, die
# pair-device.sh nach der Kopplung geschrieben hat. Ohne sie (Geraet noch
# nicht gekoppelt) gibt es nichts zu tun. Idempotent: schreibt nur bei einer
# Aenderung und startet Mosquitto dann neu. Pfade per Umgebung ueberschreibbar
# (fuer Tests ohne Pi).

Z2M_CONFIG="${Z2M_CONFIG:-/opt/zigbee2mqtt/data/configuration.yaml}"
BRIDGE_CONF="${BRIDGE_CONF:-/etc/mosquitto/conf.d/littlefarmers-bridge.conf}"
RESTART_MOSQUITTO="${RESTART_MOSQUITTO:-1}"
CA_FILE="${CA_FILE:-/etc/ssl/certs/ca-certificates.crt}"

if [[ ! -f "$Z2M_CONFIG" ]]; then
  echo "Keine Zigbee2MQTT-Konfiguration ($Z2M_CONFIG) - nichts zu tun."
  exit 0
fi

field() { grep -m1 -E "^[[:space:]]*$1:" "$Z2M_CONFIG" | sed -E "s/^[[:space:]]*$1:[[:space:]]*//; s/[[:space:]]+\$//; s/^['\"]//; s/['\"]\$//" || true; }

server="$(field server)"
user="$(field user)"
password="$(field password)"
base_topic="$(field base_topic)"

if [[ -z "$user" || -z "$password" || -z "$server" ]]; then
  echo "Geraet noch nicht gekoppelt (keine MQTT-Zugangsdaten) - keine Bridge."
  exit 0
fi
if [[ -z "$base_topic" || "$base_topic" == "zigbee2mqtt" ]]; then
  echo "Kein kundeneigener Namensraum - keine Bridge."
  exit 0
fi

address="${server#*://}"           # host:port
scheme="${server%%://*}"
if [[ "$address" != *:* ]]; then
  address="$address:1883"
fi

new_conf="$(mktemp)"
{
  echo "# Von setup-shelly-bridge.sh erzeugt - enthaelt das MQTT-Passwort des Kunden."
  echo "connection littlefarmers-cloud"
  echo "address $address"
  echo "remote_username $user"
  echo "remote_password $password"
  # Eindeutig pro Kunde: Client-IDs gelten auf dem ganzen Server, der Standard
  # (Hostname) waere bei allen Kunden "littlefarmers" und wuerde sich gegenseitig trennen.
  echo "remote_clientid lfbridge_$base_topic"
  echo "bridge_protocol_version mqttv311"
  echo "cleansession true"
  echo "start_type automatic"
  echo "restart_timeout 5 60"
  echo "notifications false"
  echo "try_private false"
  if [[ "$scheme" == "mqtts" ]]; then
    echo "bridge_cafile $CA_FILE"
  fi
  echo "topic # both 1 \"\" $base_topic/shelly/"
  echo "topic pi out 1 lf/ $base_topic/lf/"
} > "$new_conf"

if [[ -f "$BRIDGE_CONF" ]] && cmp -s "$new_conf" "$BRIDGE_CONF"; then
  rm -f "$new_conf"
  echo "Bridge-Konfiguration unveraendert."
  exit 0
fi

install -D -m 0640 "$new_conf" "$BRIDGE_CONF"
rm -f "$new_conf"
if id mosquitto >/dev/null 2>&1; then
  chown mosquitto:mosquitto "$BRIDGE_CONF" 2>/dev/null || true
fi
echo "Bridge-Konfiguration geschrieben: $BRIDGE_CONF (Namensraum $base_topic)."

if [[ "$RESTART_MOSQUITTO" == "1" ]]; then
  systemctl restart mosquitto.service
fi
