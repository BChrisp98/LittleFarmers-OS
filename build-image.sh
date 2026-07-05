#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Bitte ohne sudo starten: ./build-image.sh"
  exit 1
fi

echo "ACHTUNG: Dieses Skript bereitet den Raspberry Pi für das Kunden-Image vor."
echo "Gespeicherte WLAN-Verbindungen, Logs, SSH-Hostschlüssel und Geräte-IDs werden entfernt."
read -r -p "Fortfahren? [ja/NEIN]: " CONFIRM

if [[ "$CONFIRM" != "ja" ]]; then
  echo "Abgebrochen."
  exit 0
fi

sudo systemctl stop littlefarmers-wifi-fallback.service || true
sudo systemctl stop zigbee2mqtt.service || true

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