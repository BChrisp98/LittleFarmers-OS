# BLE-Provisioning — Stand 2026-09-06 (Nacht)

## Zusammenfassung dieser Nacht

Der erste echte Live-Test mit Handy + Pi hat stattgefunden (nach zwei
Nächten reiner Vorbereitung ohne Hardware-Test) - und dabei mehrere echte,
teils kritische Fehler gefunden, die eine Kette bildeten: erst der
eigentliche Bluetooth-Verbindungsaufbau, dann Zigbee2MQTT-Abstürze, dann
fehlende MQTT-Zugangsdaten. Alle gefunden und behoben, siehe unten im
Detail. Zwei sind so kritisch, dass sie auch rückwirkend auf `main` (den
WLAN-Hotspot-Stand) übertragen wurden, weil sie unabhängig vom
Provisioning-Weg jedes Kundengerät beim automatischen wöchentlichen
Update hätten treffen können.

## Kritische Funde dieser Nacht (auf beiden Branches, `main` + `feature/ble-provisioning`)

1. **Zigbee2MQTT trackte `master` statt einer festen Version.** Jedes
   `update.sh` (auch das wöchentliche, unbeaufsichtigte) zog die
   allerneueste Zigbee2MQTT-Version direkt von deren GitHub-Projekt -
   ungetestet von uns. Ein echter Versionssprung hat live einen Absturz
   ausgelöst ("Configuration is not consistent with adapter state/backup!").
   **Fix:** Feste, geprüfte Version (`2.14.1`) im Code verankert - künftige
   Updates kommen nur noch an, wenn wir sie selbst bewusst hochsetzen.
2. **`configuration.yaml` wurde bei jedem Update überschrieben** (dieselbe
   Fehler-Klasse wie der `system.conf`-Bug vom 23.08.). Die Vorlage hat
   `network_key/pan_id/ext_pan_id: GENERATE` - jedes Überschreiben zwang
   Zigbee2MQTT, diese Werte neu zufällig zu erzeugen, was dann nicht mehr
   zum tatsächlich auf dem Zigbee-Chip gespeicherten Stand passte -
   Absturzschleife. **Fix:** Datei wird jetzt nur beim allerersten Mal
   installiert, genau wie `system.conf`.
3. **Derselbe Effekt hat auch die vom Kopplungs-Dienst geschriebenen
   echten MQTT-Zugangsdaten gelöscht.** `littlefarmers-pair-device.service`
   läuft nur einmalig (Markierungsdatei `/var/lib/littlefarmers/paired`) -
   als sein Ergebnis durch das oben genannte Überschreiben wieder verloren
   ging, hat er sich nicht selbst repariert, weil er dachte, er sei schon
   fertig. **Einmaliger Recovery-Schritt** (nicht automatisiert, siehe
   unten) war nötig: Markierungsdatei löschen, Dienst neu anstoßen.
4. **`--experimental`-Flag für BlueZ falsch gesetzt** (nur
   `feature/ble-provisioning`): `systemctl show -p ExecStart` liefert
   KEINEN einfachen Pfad, sondern eine strukturierte Beschreibung
   (`{ path=... ; argv[]=... ; ... }`) - das alte Skript hat nur die
   öffnende Klammer `{` als "Pfad" erwischt und Bluetooth damit komplett
   lahmgelegt (`status=203/EXEC`). **Fix:** Den echten `path=`-Wert richtig
   herausgezogen, zusaetzlich geprueft, dass er wirklich eine ausfuehrbare
   Datei ist, bevor irgendwas geschrieben wird.
5. **BLE-Verbindung wurde vor Ende der Kopplung abgewürgt** (nur
   `feature/ble-provisioning`): Sobald die WLAN-Zugangsdaten bestätigt
   waren, hat der Hintergrund-Prüfprozess (der checkt "ist das alte WLAN
   zurück?") sofort das komplette Bluetooth beendet - noch bevor das Handy
   den letzten nötigen Lesevorgang (den Kopplungscode fürs Konto) machen
   konnte. Die App blieb auf "Sende WLAN-Zugangsdaten..." hängen, das
   Handy zeigte keine aktive Verbindung mehr. **Fix:** 15 Sekunden
   Pufferzeit eingebaut, bevor Bluetooth nach erfolgreicher Kopplung
   wirklich beendet wird.
6. **Kaputtes, altes WLAN-Profil blockierte neue Zugangsdaten** (nur
   `feature/ble-provisioning`): `nmcli device wifi connect` hat ein
   gleichnamiges, unvollständiges altes Profil wiederverwendet statt ein
   neues anzulegen ("key-mgmt: property is missing"). **Fix:** Vorheriges
   Profil mit demselben Namen wird jetzt immer zuerst gelöscht.

## App-seitige Ergänzungen dieser Nacht

- **WLAN-QR-Code-Scanner** als Alternative zum Passwort-Eintippen (echtes
  Apple-artiges automatisches Passwort-Teilen ist für Drittanbieter-Apps
  auf keinem Betriebssystem möglich - das ist die technisch beste
  Annäherung).
- **Bluetooth-Aus-Erkennung** mit direktem "Bluetooth einschalten"-Knopf
  in der App (ein Tap statt Wechsel in die Handy-Einstellungen).
- **Zeitüberschreitungen für jede Bluetooth-Operation** (20s) - vorher
  konnte die App bei einem Verbindungsproblem unbegrenzt und ohne
  Fehlermeldung hängen bleiben ("Verbinden geklickt, nix passiert").
- **Direkter Bluetooth-Einrichtungs-Button auf dem Start-Bildschirm**
  (wenn noch keine Pflanze angelegt ist) - kein Umweg über die
  Einstellungen nötig für die Ersteinrichtung.
- **Pairing-Zeitfenster für Sensoren von 120s auf 254s verlängert** -
  entspricht jetzt Zigbee2MQTTs eigenem Standardwert.
- **Neue Geräte-Übersicht** (`lib/screens/device_overview_screen.dart`) -
  zeigt alle gekoppelten Sensoren/Aktoren, ob sie gerade erreichbar sind,
  und erlaubt Entfernen. Braucht `availability: true` in Zigbee2MQTTs
  Konfiguration (jetzt Teil der Vorlage) - auf dem aktuellen Test-Pi
  einmalig manuell nachzutragen (siehe Kommentar in
  `config/zigbee2mqtt.yaml`).

## Wo der Code liegt

Wie vorher: `main` = zuletzt funktionierender WLAN-Hotspot-Stand (jetzt
zusätzlich mit den kritischen Zigbee2MQTT-Fixes), `feature/ble-provisioning`
= aktueller Bluetooth-Weg samt aller Fixes von heute Nacht. Beide Repos
(Pi + App) haben beide Branches, App lokal (kein Remote).

## Was als Nächstes ansteht

1. **Nous-Zigbee-Steckdose koppeln** - der eigentliche Grund, warum die
   ganze Fehlerkette heute Nacht überhaupt sichtbar wurde. Mit allen
   Fixes (Zigbee2MQTT stabil, echte MQTT-Zugangsdaten, längeres
   Pairing-Fenster) sollte das jetzt klappen - noch nicht final bestätigt,
   der Test wurde mitten in der Nacht unterbrochen.
2. Sobald das steht: die eigentliche Ende-zu-Ende-Bestätigung des
   kompletten Ablaufs (Pi ohne WLAN → Bluetooth → App → Kopplung → Sensor
   hinzufügen) einmal am Stück, ohne Unterbrechung.
3. Danach: Golden Image ziehen, Branches mergen.
