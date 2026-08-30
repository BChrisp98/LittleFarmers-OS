#!/usr/bin/env bash
set -uo pipefail

# Wipes every saved WLAN-Verbindung (nur WiFi-Profile, Ethernet/loopback
# bleiben unangetastet) - fuer zwei Faelle gedacht:
#
#   1. Vor jedem Golden-Image-Capture: ein Image darf NIE eigene
#      WLAN-Passwoerter enthalten (Testrouter, privates WLAN, etc.) -
#      das waere ein echtes Sicherheits-/Datenschutzproblem fuer jeden
#      Kunden, der ein daraus geflashtes Geraet bekommt.
#   2. Fuer einen sauberen "frisch wie beim Kunden"-Testzustand, ohne
#      dass alte Test-Profile (Handy-Hotspot, Router, etc.) den
#      Fallback-Mechanismus verfaelschen.
#
# Bewusst ein manuelles, eigenstaendiges Skript - laeuft NIE automatisch
# (nicht Teil von update.sh/firstboot.sh), weil es sonst ein bereits
# gekoppeltes Kundengeraet von seinem echten WLAN trennen wuerde. Nur
# von Hand ausfuehren, wenn genau das gewollt ist.

if [[ $EUID -ne 0 ]]; then
  echo "Bitte mit sudo ausfuehren: sudo ./scripts/clear-wifi-profiles.sh"
  exit 1
fi

echo "Folgende WLAN-Profile werden geloescht:"
nmcli -t -f UUID,TYPE,NAME connection show | awk -F: '$2=="802-11-wireless" {print "  - " $3}'

nmcli -t -f UUID,TYPE connection show \
  | awk -F: '$2=="802-11-wireless" {print $1}' \
  | while read -r uuid; do
      nmcli connection delete "$uuid" >/dev/null 2>&1 || true
    done

echo "Fertig - keine gespeicherten WLAN-Profile mehr vorhanden."
