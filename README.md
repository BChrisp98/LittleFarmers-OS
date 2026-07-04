# LittleFarmers OS

LittleFarmers OS richtet einen frisch installierten Raspberry Pi automatisch für den Betrieb als LittleFarmers-Zentrale ein.

## Enthaltene Funktionen

- Hostname `littlefarmers`
- Erreichbarkeit über `littlefarmers.local`
- SSH im Autostart
- NetworkManager für WLAN
- WiFi-Fallback mit Captive Portal
- Hotspot `LittleFarmers`
- Zigbee2MQTT im Autostart
- Zigbee2MQTT-Weboberfläche auf Port 8080
- Verbindung zum externen MQTT-Server

## Voraussetzungen

- Raspberry Pi OS 64-bit
- Benutzername `littlefarmers`
- funktionierende Internetverbindung während der Installation
- unterstützter Zigbee-USB-Koordinator

## Installation

```bash
chmod +x install.sh
./install.sh
sudo reboot