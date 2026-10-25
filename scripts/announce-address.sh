#!/usr/bin/env bash
set -u

# Meldet die Heimnetz-Adresse dieses Geraets als gespeicherte Nachricht
# (lf/pi, ueber die Bridge nach <Namensraum>/lf/pi). Die App zeigt sie unter
# "Shelly einrichten" als Adresse, die der Kunde in den Shelly eintraegt.

while true; do
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)"
  if [[ -n "$ip" ]]; then
    mosquitto_pub -h 127.0.0.1 -p 1883 -t lf/pi -r -q 1 -m "{\"ip\":\"$ip\"}" >/dev/null 2>&1 || true
  fi
  sleep 60
done
