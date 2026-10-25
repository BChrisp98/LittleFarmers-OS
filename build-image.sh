#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Bitte ohne sudo starten: ./build-image.sh"
  exit 1
fi

echo "ACHTUNG: Dieses Skript bereitet den Raspberry Pi für das Kunden-Image vor."
echo "Gespeicherte WLAN-Verbindungen, Logs, SSH-Hostschlüssel und Geräte-IDs werden entfernt."
if [[ "${1:-}" == "--yes" ]]; then
  CONFIRM="ja"
else
  read -r -p "Fortfahren? [ja/NEIN]: " CONFIRM
fi

if [[ "$CONFIRM" != "ja" ]]; then
  echo "Abgebrochen."
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Das Image muss genau dem Stand auf GitHub entsprechen, sonst scheitert das
# Self-Update beim Kunden ("git pull --ff-only" bei lokalen Aenderungen).
git -C "$PROJECT_ROOT" fetch --quiet origin
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]] \
   || [[ "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" != "$(git -C "$PROJECT_ROOT" rev-parse '@{u}')" ]]; then
  echo "FEHLER: Das Repo auf dem Pi hat lokale Aenderungen oder weicht von GitHub ab."
  echo "Erst auf GitHub hochladen und hier 'git reset --hard @{u}' ausfuehren."
  exit 1
fi

sudo systemctl stop littlefarmers-wifi-fallback.service || true
sudo systemctl stop zigbee2mqtt.service || true

# Zigbee-Netz dieses Entwicklungsgeraets entfernen: Netzwerkschluessel,
# Geraete, Backup. Sonst haetten ALLE Kunden dasselbe Funknetz und denselben
# Schluessel. Die Vorlage hat "GENERATE" - Zigbee2MQTT erzeugt beim ersten
# Start beim Kunden eigene Werte.
sudo rm -f /opt/zigbee2mqtt/data/database.db /opt/zigbee2mqtt/data/database.db.backup \
  /opt/zigbee2mqtt/data/coordinator_backup.json /opt/zigbee2mqtt/data/state.json \
  /opt/zigbee2mqtt/data/devices.yaml /opt/zigbee2mqtt/data/groups.yaml
sudo rm -rf /opt/zigbee2mqtt/data/log
sudo install -o littlefarmers -g littlefarmers -m 0640 \
  "$PROJECT_ROOT/config/zigbee2mqtt.yaml" /opt/zigbee2mqtt/data/configuration.yaml

# Zustand dieses Geraets: Kopplung, Passwort, Kopplungscode, Self-Update-Marker.
# Alles wird beim Kunden neu erzeugt (firstboot.sh) bzw. das Self-Update laeuft
# dort einmalig.
sudo rm -f /var/lib/littlefarmers/initial-password /var/lib/littlefarmers/paired \
  /var/lib/littlefarmers/self-update-complete /etc/littlefarmers/device-code
rm -f "$HOME/install.log" "$HOME/.ssh/authorized_keys"

# Vom Raspberry Pi Imager geschriebene Einstellungen dieses Entwicklungsgeraets
# (Hostname, Passwort-Hash, SSH-Schluessel, WLAN) durch neutrale Werte ersetzen
# und den cloud-init-Zustand loeschen, damit auch dessen interne Kopien weg sind.
sudo tee /boot/firmware/user-data >/dev/null <<'EOF'
#cloud-config
hostname: littlefarmers
manage_etc_hosts: true
timezone: Europe/Berlin
keyboard:
  model: pc105
  layout: "de"
users:
- name: littlefarmers
  groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
  shell: /bin/bash
  lock_passwd: false
  sudo: ALL=(ALL) NOPASSWD:ALL
EOF
sudo tee /boot/firmware/network-config >/dev/null <<'EOF'
network:
  version: 2
EOF
sudo cloud-init clean --logs || true

# Kunden bekommen eine schlanke Oberflaeche-lose Basis (Einrichtung per App).
sudo systemctl set-default multi-user.target

# WLAN-Zugangsdaten des Entwicklungsnetzes entfernen
sudo rm -f /etc/NetworkManager/system-connections/*.nmconnection

# First-Boot beim Kunden erneut ausführen
sudo rm -f /var/lib/littlefarmers/firstboot-complete

# Eindeutige Gerätekennungen zurücksetzen
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

# SSH-Hostschlüssel werden beim ersten Kundenstart neu erzeugt
sudo rm -f /etc/ssh/ssh_host_*

# Temporären GitHub-Zugang und bekannte SSH-Server entfernen
rm -f "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
rm -f "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts.old"
sudo rm -f /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub
sudo rm -f /root/.ssh/known_hosts /root/.ssh/known_hosts.old

# Alte Netzwerk-Leases und temporäre NetworkManager-Daten entfernen
sudo rm -f /var/lib/NetworkManager/*.lease
sudo rm -f /var/lib/dhcp/*

# Logs und temporäre Daten entfernen
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
sudo rm -rf /tmp/*
sudo apt-get clean

history -c || true
rm -f "$HOME/.bash_history"

sync

echo
echo "Golden-Image-Vorbereitung abgeschlossen."
echo "Der Raspberry Pi wird jetzt heruntergefahren."
echo "Danach SD-Karte entnehmen und als vollständiges .img auslesen."

sudo poweroff