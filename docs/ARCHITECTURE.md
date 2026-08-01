# LittleFarmers OS – Architektur

## Ziel

Ein fertig vorbereitetes Raspberry-Pi-System für Kunden.

Nach dem Flashen und Einschalten startet alles automatisch.

## Hostname

- Hostname: `littlefarmers`
- Lokale Adresse: `littlefarmers.local`

## Dienste im Autostart

- NetworkManager
- SSH
- Avahi
- Zigbee2MQTT
- LittleFarmers WiFi Fallback

## Dienste, die nicht dauerhaft laufen

- WiFi Connect
- hostapd
- comitup
- comitup-web

WiFi Connect wird ausschließlich vom Fallback-Dienst gestartet.

## Zigbee2MQTT

- Weboberfläche: `http://littlefarmers.local:8080`
- Externer MQTT-Server: `mqtt://18.193.124.166:1883` (Stand 2026-07-25 -
  keine Elastic IP, kann sich beim nächsten Neustart der Instanz wieder
  ändern, siehe Vendor-Liste.md)
- Kein lokaler MQTT-Broker
- Kein MQTT-Benutzername
- Kein MQTT-Passwort

## WLAN-Normalbetrieb

Wenn eine funktionierende Internetverbindung vorhanden ist:

- Der Raspberry Pi bleibt im gespeicherten WLAN.
- Der LittleFarmers-Hotspot bleibt ausgeschaltet.
- Zigbee2MQTT läuft weiter.

## WLAN-Fallback

Wenn 15 Minuten lang keine Internetverbindung vorhanden ist:

1. Der Hotspot `LittleFarmers` wird gestartet.
2. Der Hotspot ist offen und benötigt kein Passwort.
3. Das Captive Portal wird auf Port 80 gestartet.
4. Der Kunde wählt ein WLAN aus.
5. Der Kunde gibt das WLAN-Passwort ein.
6. NetworkManager speichert die Verbindung.
7. Bei erfolgreicher Verbindung wird der Hotspot beendet.

Wenn keine neue Verbindung eingerichtet wurde:

1. Der Hotspot bleibt maximal 15 Minuten aktiv.
2. Danach versucht der Raspberry Pi erneut, bekannte WLANs zu verbinden.
3. Besteht weiterhin keine Internetverbindung, beginnt der Ablauf erneut.

## Ports

- `22`: SSH
- `80`: Captive Portal
- `8080`: Zigbee2MQTT

## Golden Image

Das Repository installiert und konfiguriert einen frischen Raspberry Pi.

Nach erfolgreichem Test wird aus der vorbereiteten SD-Karte ein Golden Image erstellt.

Der Kunde muss anschließend nur:

1. das LittleFarmers-Image flashen,
2. die SD-Karte einsetzen,
3. den Raspberry Pi einschalten.