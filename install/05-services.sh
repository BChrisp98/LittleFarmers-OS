#!/usr/bin/env bash
set -euo pipefail

echo "=== LittleFarmers: Dienste installieren ==="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Dieses Skript muss mit sudo ausgeführt werden."
  exit 1
fi

install -m 0644 \
  "$PROJECT_ROOT/services/zigbee2mqtt.service" \
  /etc/systemd/system/zigbee2mqtt.service

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-wifi-fallback.service" \
  /etc/systemd/system/littlefarmers-wifi-fallback.service

install -m 0755 \
  "$PROJECT_ROOT/scripts/wifi-fallback.sh" \
  /usr/local/bin/littlefarmers-wifi-fallback.sh

# BLE-Provisioning ersetzt ab hier (feature/ble-provisioning-Branch,
# 2026-08-30) den WLAN-Hotspot als primaeren Weg. Das alte Skript/der
# alte Dienst bleiben installiert (siehe oben) als Rueckfalloption, falls
# BLE sich nicht bewaehrt - werden unten aber bewusst NICHT aktiviert,
# damit nicht beide Mechanismen gleichzeitig um wlan0 konkurrieren.
install -m 0755 \
  "$PROJECT_ROOT/scripts/ble_provisioning.py" \
  /usr/local/bin/littlefarmers-ble-provisioning.py

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-ble-provisioning.service" \
  /etc/systemd/system/littlefarmers-ble-provisioning.service

# Sicherheitsfund 2026-08-16: nach der Kopplung (pair-device.sh) enthaelt
# diese Datei das Klartext-MQTT-Passwort des Kunden - 0644 waere fuer
# jeden lokalen Prozess auf dem Geraet lesbar. 0640 reicht: root schreibt
# (pair-device.sh laeuft als root), littlefarmers-Nutzer liest (das
# zigbee2mqtt.service laeuft als dieser, siehe services/zigbee2mqtt.service).
install -m 0640 \
  "$PROJECT_ROOT/config/zigbee2mqtt.yaml" \
  /opt/zigbee2mqtt/data/configuration.yaml

# Zigbee2MQTT muss seine Konfiguration und Daten verändern können.
chown -R littlefarmers:littlefarmers /opt/zigbee2mqtt

mkdir -p /etc/littlefarmers

# Sicherheitsfund 2026-08-16: enthaelt nach der Kopplung ebenfalls den
# MQTT-Broker (MQTT_SERVER) - nur root braucht diese Datei (pair-device.sh
# und wifi-fallback.sh laufen beide als root, siehe services/*.service),
# daher 0600 statt 0644.
#
# Kritischer Fund 2026-08-23, im Zuge des woechentlichen Auto-Updates
# (siehe littlefarmers-update.timer weiter unten): Dieser install-Befehl
# lief bisher bedingungslos bei JEDEM Durchlauf und haette damit die
# echten MQTT-Zugangsdaten, die pair-device.sh nach erfolgreicher
# Kopplung per sed -i in genau diese Datei schreibt, jede Woche wieder
# auf die Platzhalter-Werte der Repo-Vorlage zurueckgesetzt - ein bereits
# gekoppeltes Kundengeraet haette sich damit selbst laufend die eigene
# Verbindung zerschossen. Nur beim allerersten Mal installieren (Datei
# existiert noch nicht); danach bleibt sie unangetastet, auch bei
# zukuenftigen neuen Feldern in der Vorlage (die brauchen dann eine
# gezielte Migration, kein blindes Ueberschreiben).
if [[ ! -f /etc/littlefarmers/system.conf ]]; then
  install -m 0600 \
    "$PROJECT_ROOT/config/system.conf" \
    /etc/littlefarmers/system.conf
fi

install -m 0755 \
  "$PROJECT_ROOT/scripts/firstboot.sh" \
  /usr/local/bin/littlefarmers-firstboot.sh

install -m 0644 \
  "$PROJECT_ROOT/services/firstboot.service" \
  /etc/systemd/system/firstboot.service

install -m 0755 \
  "$PROJECT_ROOT/scripts/pair-device.sh" \
  /usr/local/bin/littlefarmers-pair-device.sh

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-pair-device.service" \
  /etc/systemd/system/littlefarmers-pair-device.service

install -m 0755 \
  "$PROJECT_ROOT/scripts/self-update-firstboot.sh" \
  /usr/local/bin/littlefarmers-self-update.sh

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-self-update.service" \
  /etc/systemd/system/littlefarmers-self-update.service

# Woechentliches Update, damit Geraete beim Kunden dauerhaft aktuell
# bleiben statt nur einmalig beim allerersten Boot (Christoph, 2026-08-23:
# einmal im Monat reicht nicht - woechentlich).
install -m 0755 \
  "$PROJECT_ROOT/scripts/weekly-update.sh" \
  /usr/local/bin/littlefarmers-weekly-update.sh

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-update.service" \
  /etc/systemd/system/littlefarmers-update.service

install -m 0644 \
  "$PROJECT_ROOT/services/littlefarmers-update.timer" \
  /etc/systemd/system/littlefarmers-update.timer

systemctl daemon-reload

systemctl enable NetworkManager.service
systemctl enable avahi-daemon.service
systemctl enable ssh.service
systemctl enable bluetooth.service
systemctl enable zigbee2mqtt.service
systemctl enable firstboot.service
systemctl enable littlefarmers-pair-device.service
systemctl enable littlefarmers-self-update.service
systemctl enable --now littlefarmers-update.timer

# BLE-Provisioning ist jetzt der primaere Mechanismus - der alte
# WLAN-Hotspot-Dienst bleibt bewusst deaktiviert (nicht deinstalliert),
# damit beide nicht gleichzeitig um wlan0 konkurrieren. Zum Zurueckwechseln:
# `sudo systemctl disable --now littlefarmers-ble-provisioning &&
#  sudo systemctl enable --now littlefarmers-wifi-fallback`
systemctl disable --now littlefarmers-wifi-fallback.service 2>/dev/null || true
systemctl enable littlefarmers-ble-provisioning.service

echo "=== Dienste installiert und für Autostart aktiviert ==="