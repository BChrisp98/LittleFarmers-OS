#!/usr/bin/env bash
set -u

echo "========================================"
echo " LittleFarmers OS – Systemcheck"
echo "========================================"

check_service() {
  local service="$1"

  if systemctl is-active --quiet "$service"; then
    echo "[OK]     $service läuft"
  else
    echo "[FEHLER] $service läuft nicht"
  fi
}

check_enabled() {
  local service="$1"

  if systemctl is-enabled --quiet "$service"; then
    echo "[OK]     $service ist im Autostart"
  else
    echo "[FEHLER] $service ist nicht im Autostart"
  fi
}

echo
echo "Hostname:"
hostname

echo
echo "Dienste:"
check_service NetworkManager.service
check_service avahi-daemon.service
check_service ssh.service
check_service littlefarmers-wifi-fallback.service
check_service zigbee2mqtt.service

echo
echo "Autostart:"
check_enabled NetworkManager.service
check_enabled avahi-daemon.service
check_enabled ssh.service
check_enabled littlefarmers-wifi-fallback.service
check_enabled zigbee2mqtt.service

echo
echo "Programme:"
command -v node >/dev/null && echo "[OK]     Node.js installiert" || echo "[FEHLER] Node.js fehlt"
command -v pnpm >/dev/null && echo "[OK]     pnpm installiert" || echo "[FEHLER] pnpm fehlt"
command -v wifi-connect >/dev/null && echo "[OK]     WiFi Connect installiert" || echo "[FEHLER] WiFi Connect fehlt"

echo
echo "Netzwerk:"
if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
  echo "[OK]     Internet erreichbar"
else
  echo "[HINWEIS] Kein Internet erreichbar"
fi

echo
echo "Zigbee-Adapter:"
if ls /dev/serial/by-id/* >/dev/null 2>&1; then
  ls -1 /dev/serial/by-id/
else
  echo "[HINWEIS] Kein Zigbee-Adapter gefunden"
fi

echo
echo "========================================"
echo " Systemcheck abgeschlossen"
echo "========================================"