# Frischer Pi: Neues Abbild bauen und von null testen (Stand 2026-10-23)

Ziel: Ein Pi, so wie ihn ein Kunde bekommt, wird mit dem Konto eines fremden
Handys gekoppelt – ohne dass ich etwas am Server von Hand zurechtbiege.

## Was sich seit dem alten Abbild (2026-07-05) geändert hat – darum geht das alte Abbild nicht mehr
- Der Server ist nur noch über **HTTPS** erreichbar (`https://api.littlefarmers-shop.com`). Der alte Port 8000 ist zu.
  Ein Pi mit dem alten Abbild findet den Server nicht mehr und **kann sich nicht mehr koppeln**.
- Das Koppel-Skript (`scripts/pair-device.sh`) und `config/system.conf` sind angepasst:
  HTTPS und – sobald der Server Port 8883 vergibt – verschlüsselter MQTT-Zugang (`mqtts://`).
- Bereits gekoppelte Pis (zum Beispiel dein Test-Pi) laufen unverändert weiter.

## Weg A (empfohlen für morgen): Frischer Pi, alles von null, ohne Abbild
Man braucht: SD-Karte, Raspberry Pi, den Zigbee-USB-Stick, WLAN-Daten, dein Handy mit der App und ein **zweites Testkonto**.

1. **SD-Karte beschreiben:** Programm "Raspberry Pi Imager" öffnen → Gerät: dein Pi-Modell → Betriebssystem: *Raspberry Pi OS Lite (64-bit)* → Zahnrad/"Einstellungen bearbeiten":
   - Hostname `littlefarmers`
   - Benutzername `littlefarmers`, ein Passwort, das du dir merkst
   - SSH aktivieren
   - WLAN: dein Heimnetz (nur für die Installation)
2. SD-Karte in den Pi, Strom an, 3 Minuten warten.
3. **Dateien auf den Pi kopieren** (Windows, Eingabeaufforderung oder PowerShell):
   ```
   scp -r "D:\OneDrive\00.Little-Farmers\03.Produkte\04.App\Raspberry Pi\LittleFarmers-OS" littlefarmers@littlefarmers.local:~/
   ```
4. **Installieren** (Verbindung zum Pi: `ssh littlefarmers@littlefarmers.local`):
   ```
   cd ~/LittleFarmers-OS
   chmod +x install.sh
   ./install.sh
   sudo reboot
   ```
   Das dauert 10–20 Minuten.
5. **Kopplungscode lesen** (nach dem Neustart wieder per SSH): `cat /etc/littlefarmers/device-code`
6. In der App mit dem **Testkonto** einloggen → Plus/Geräte → Pi koppeln → Code eingeben.
7. Beobachten: Innerhalb von etwa 5–10 Sekunden holt sich der Pi die Zugangsdaten. Im Pi: `sudo journalctl -u littlefarmers-pair-device -n 20` – dort steht "Kopplung abgeschlossen".
8. Zigbee-Gerät anlernen, Pflanze anlegen, Geräte zuordnen, Lampe schalten.

## Weg B: Neues Kundenabbild (Golden Image) erzeugen
Erst wenn Weg A einmal sauber durchgelaufen ist:
1. Auf dem fertig installierten Pi (vor dem Koppeln!) `./build-image.sh` ausführen – es löscht WLAN-Daten, Gerätekennungen, SSH-Schlüssel und fährt den Pi herunter.
2. SD-Karte in den PC, mit *Win32 Disk Imager* oder *Raspberry Pi Imager* ("Backup"/"Read") als `.img` auslesen.
3. Datei als `LittleFarmers-OS-Golden-Image-2026-10-xx.img` ablegen. Das alte Abbild vom Juli bitte **nicht mehr verwenden**.
4. Das Abbild mit einem zweiten, frischen Pi testen (Schritte 5–8 von oben).

## Entscheidungen / Hinweise
- **Dein Geschäftsmodell (nur Software, keine Geräte):** Kunden brauchen dann eine Anleitung wie Weg A oder das fertige Abbild zum Herunterladen. Ein Abbild zum Download muss irgendwo liegen (zum Beispiel im S3-Speicher) – das ist ein eigener Schritt für später.
- **Das GitHub-Repo `BChrisp98/LittleFarmers-OS` ist öffentlich.** Der automatische Update-Mechanismus der Pis (Self-Update beim ersten Start) lädt von dort. Das ist bequem, aber alles darin ist für jeden lesbar, zum Beispiel das Hotspot-Passwort `LittleFarmers2026!`. Der Hotspot läuft nur beim WLAN-Einrichten (etwa 15 Minuten). Besser wäre die Einrichtung per Bluetooth über die App; dann lässt sich der Hotspot ganz abschalten.
- Die Änderungen sind lokal als Commit vorbereitet, aber **noch nicht auf GitHub hochgeladen**. Ohne Hochladen funktioniert Weg A trotzdem (Dateien kommen per `scp` vom PC).
