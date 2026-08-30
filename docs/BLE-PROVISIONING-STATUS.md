# BLE-Provisioning — Stand nach der Nacht 2026-08-30 → 2026-08-31

Gebaut auf Wunsch von Christoph, während er geschlafen hat. Ersetzt den
WLAN-Hotspot/Captive-Portal-Ansatz (siehe `scripts/wifi-fallback.sh`,
weiterhin vorhanden als Rückfalloption, siehe unten) durch Bluetooth Low
Energy (BLE) als primären Weg für die WLAN-Ersteinrichtung.

**Wichtig: Noch nie gegen echte Hardware getestet.** Alles unten ist
sorgfältig gebaut und wo möglich geprüft (Syntax, `flutter analyze`,
kompletter Release-Build), aber ein echtes Bluetooth-Pairing zwischen
Handy und Pi hat noch nie stattgefunden. Das ist der wichtigste nächste
Schritt.

## Wo der Code liegt

- **Pi:** Branch `feature/ble-provisioning` im Repo
  `BChrisp98/LittleFarmers-OS` (nicht `main` — `main` hat weiterhin den
  funktionierenden, zuletzt getesteten WLAN-Hotspot-Stand, getaggt als
  `wifi-hotspot-working-checkpoint`).
- **App:** Branch `feature/ble-provisioning` im lokalen Repo unter
  `App-Rebuild` (war vorher gar nicht unter Git — jetzt ist es das, mit
  `main` als sauberer Ausgangspunkt).

## Was fertig ist

- `scripts/ble_provisioning.py` — Python-Dienst auf dem Pi, der per
  `bluezero` einen BLE-GATT-Server aufmacht. Zustandsautomat: normal
  online → NetworkManager verbindet automatisch das gespeicherte
  „Customer-WiFi"-Profil; 120 Sekunden offline → BLE-Advertising startet;
  alle 30 Sekunden erneut prüfen, ob das alte WLAN wieder da ist → sofort
  beenden, sobald ja; neue Zugangsdaten werden **erst getestet, bevor**
  das alte Profil angefasst wird (ein Tippfehler beim Passwort darf den
  Kunden nicht von beiden WLANs aussperren).
- GATT-Protokoll (Service-UUID `6c85f000-...`): `NETWORKS` (WLAN-Liste
  lesen), `CREDENTIALS` (neues WLAN schreiben), `STATUS`
  (idle/connecting/testing/connected/failed, mit Notify), `DEVICE_CODE`
  (liest den existierenden Kopplungscode — nutzt den bereits vorhandenen
  Account-Kopplungs-Mechanismus wieder, keine neue Backend-Logik nötig).
- `install/06-ble-provisioning.sh` — installiert `bluez`, `python3-dbus`,
  `python3-gi`, `bluezero` (pip). Setzt außerdem BlueZ auf den
  `--experimental`-Modus (per systemd-Override, nicht durch Bearbeiten der
  Originaldatei) — das ist zwingend nötig, damit der GATT-Peripheral-Modus
  überhaupt funktioniert, sonst schlägt `bluezero` beim Start fehl. Per
  Recherche bestätigt, aber **nicht** an echter Hardware verifiziert.
- `install/05-services.sh` — installiert/aktiviert
  `littlefarmers-ble-provisioning.service`, deaktiviert (nicht deinstalliert)
  `littlefarmers-wifi-fallback.service`, damit beide nicht gleichzeitig um
  `wlan0` konkurrieren. Zurückwechseln:
  ```bash
  sudo systemctl disable --now littlefarmers-ble-provisioning
  sudo systemctl enable --now littlefarmers-wifi-fallback
  ```
- App: `lib/services/ble_provisioning_service.dart` (Client-Seite des
  Protokolls, `flutter_blue_plus`) und `lib/screens/ble_setup_screen.dart`
  (Scan → WLAN wählen → Passwort → Live-Status → automatische
  Kontokopplung über den existierenden `claimDevice`-Aufruf). In den
  Einstellungen ist „Gerät einrichten" (Bluetooth) jetzt der Haupteintrag,
  „Gerät koppeln (Code)" bleibt als expliziter Rückfall daneben stehen.
- Android-Berechtigungen (`BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`/Location für
  ältere Geräte) sind im Manifest ergänzt. Kein iOS-Projekt vorhanden,
  daher auch keine `Info.plist`-Anpassung nötig.
- **Geprüft:** `flutter analyze` läuft sauber (nur zwei harmlose
  Deprecation-Hinweise zu `RadioListTile`, keine Fehler). Ein kompletter
  `flutter build apk --release` läuft erfolgreich durch.

## Nachtrag: zwei echte Bugs gefunden und gefixt (ohne Hardware, per Quellcode-Lektüre)

Statt bei den `bluezero`-Aufrufen zu raten, hab ich den echten Quellcode
von `bluezero` direkt von GitHub gezogen (`gh api repos/ukBaz/python-bluezero/...`)
und gegengeprüft. Dabei zwei echte Fehler gefunden, die sonst erst beim
ersten Live-Test aufgefallen wären:

1. `Peripheral.stop()` existiert gar nicht — der Code rief das versehentlich
   auf, um das Advertising zu beenden. Fix: `periph.mainloop.quit()` direkt
   (das ist der tatsächlich existierende, offiziell Thread-sichere Weg).
2. Status-Änderungen (`connecting`/`testing`/`connected`/`failed`) haben nie
   wirklich eine Benachrichtigung ausgelöst — nur ein internes Dict wurde
   aktualisiert, aber `Characteristic.set_value()` (das intern das
   `PropertiesChanged`-Signal auslöst) wurde nie aufgerufen. Fix: die
   Zeichen-Referenz wird jetzt beim Aufbau eingesammelt und bei jedem
   Status-Wechsel genutzt.

Beide Fixes sind committet (`68b3e2f`, `a7dddd4`). Das erhöht die
Zuversicht deutlich, ersetzt aber nicht den echten Hardware-Test.

## Was NICHT geprüft ist (der eigentliche Test für morgen)

1. **Erstes echtes Pairing.** Pi mit dem neuen Branch aktualisieren,
   Handy-App mit dem neuen Branch neu bauen und installieren, dann den
   kompletten Weg einmal live durchgehen: Pi offline → Bluetooth erscheint
   → App findet es → WLAN auswählen → verbinden → Status live verfolgen →
   Kopplung mit dem Konto.
2. Ob `--experimental` auf genau dieser BlueZ-Version wirklich reicht,
   oder ob noch was fehlt (D-Bus-Berechtigungen, `bluetoothd`-Policy-Datei,
   o.ä.) — das lässt sich nur an echter Hardware erkennen.
3. Timing-Feingefühl: sind 120 Sekunden bis BLE startet und 30 Sekunden
   Re-Check-Intervall wirklich gut fürs echte Erlebnis? Lässt sich leicht
   in `scripts/ble_provisioning.py` (`OFFLINE_TIMEOUT`,
   `WIFI_RECHECK_INTERVAL`) anpassen.
4. Sicherheitsfrage, bewusst offen gelassen (siehe Kommentar im Code):
   GATT-Schreibzugriffe sind aktuell nicht extra verschlüsselt, verlassen
   sich auf BLE-eigenes Pairing/Bonding. Für den ersten Test okay, für den
   Kunden-Rollout nochmal bewusst entscheiden.

## So geht's morgen weiter

```bash
# Auf dem Pi:
cd ~/LittleFarmers-OS
git fetch
git checkout feature/ble-provisioning
git pull
./update.sh
sudo journalctl -u littlefarmers-ble-provisioning -f   # live mitlesen
```

App-Seite: `flutter build apk --release` auf `feature/ble-provisioning`
im `App-Rebuild`-Ordner, auf dem Handy installieren, dann den Ablauf
live durchspielen.

**Falls es nicht klappt:** `main` in beiden Repos hat den unangetasteten,
zuletzt funktionierenden WLAN-Hotspot-Stand — einfach dorthin zurück, kein
Fortschritt von der Nacht geht dabei verloren.
