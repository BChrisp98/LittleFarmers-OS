# Broker-Sicherheit / Kundentrennung - Umsetzungsplan

**Update 2026-08-15: Entscheidung gefallen - Option B.** Christoph: "Kunden
können das eigenständig nicht, deswegen muss ich das denen vorbereiten...
wir können uns nicht auf den Lieferanten verlassen." Eigener Server
(`18.159.76.112`, wo das Backend schon läuft) statt Lieferanten-Broker.
Umsetzung: `Backend/server.py` `_claim_device` provisioniert jetzt
automatisch den Mosquitto-Zugang jedes Kunden (Passwort + ACL, siehe
`Backend/littlefarmers-mqtt-provision.sh` und `Backend/DEPLOY.md`), die
Pi-seitigen Konfigurationsdateien (`config/system.conf`,
`config/zigbee2mqtt.yaml`) zeigen jetzt auf den eigenen Server statt auf
`63.184.28.93`. Serverseitige Mosquitto-Installation + Deploy steht noch
aus (braucht Christoph im Terminal), Code ist fertig.

Stand: 2026-08-09/10 (Nacht), vorbereitet während Christophs Abwesenheit.
**Nichts hiervon ist live geschaltet** - App-seitig sind die nötigen Felder
jetzt vorbereitet (siehe unten), aber die eigentliche Broker-Konfiguration
(Mosquitto-Passwort, ACLs, Pi-Provisionierung) ist noch nicht angefasst,
wie besprochen (keine Produktions-Systeme selbst anfassen).

## Wichtige Korrektur zur bisherigen Annahme

In einem früheren Nachtrag hatte ich geschrieben, du müsstest dir "Admin-
Zugriff auf den Broker verschaffen". Das ist so nicht ganz richtig -
`Vendor-Liste.md` (dein eigenes Dokument, Stand 2026-08-02) zeigt klar:
**`63.184.28.93` ist die Infrastruktur des Lieferanten**, nicht dein
eigener Server. Punkt 4b dort ("MQTT-Broker ohne Zugangsdaten
erreichbar") und 4c ("keine Datentrennung zwischen Accounts") sind
bereits von dir an den Lieferanten gemeldet worden - du warst dir des
Problems also schon bewusst, ich habe hier nichts Neues entdeckt,
sondern nur (aus App-Sicht) bestätigt, dass es real ist.

Das bedeutet: die Entscheidung ist nicht "wie fixe ich das selbst",
sondern eine von zwei Optionen:

**Option A - Lieferant fixt seinen Broker.** Nachfragen/eskalieren, ob
Punkt 4b/4c inzwischen bearbeitet wurden. Falls ja: der Lieferant müsste
dann pro Kunde einen MQTT-Benutzer + ACL einrichten (Vorlage unten) -
das kannst nur er umsetzen, da es sein Server ist.

**Option B - Migration auf deinen eigenen Server** (`18.159.76.112`,
wo unser Backend schon läuft). Du hättest volle Kontrolle, aber jeder
Kunden-Pi müsste umkonfiguriert werden (neue Broker-Adresse), und Hanfis
echte Geräte müssten mit-migriert werden, ohne den laufenden Betrieb zu
stören. Größerer, aber sichererer Schritt.

Das ist deine Entscheidung - ich habe unten die App-seitige Vorbereitung
gemacht, die für BEIDE Optionen identisch gebraucht wird, damit keine
Zeit verloren geht, sobald du dich entschieden hast.

## Was jetzt vorbereitet ist (lokal, ungetestet gegen echte Mehrkunden-Situation)

1. **Backend** (`Backend/server.py`): neue Spalte `mqtt_base_topic` in
   der `users`-Tabelle, zusätzlich zu den schon bestehenden
   `mqtt_host`/`mqtt_port`/`mqtt_username`/`mqtt_password` (die gab es
   schon aus einer früheren Runde). `NULL` = Standard `zigbee2mqtt`,
   genau wie bisher - keine bestehende Funktionalität ändert sich.
   `/api/me` liefert das Feld jetzt mit aus, `/api/me/broker` kann es
   jetzt mitsetzen.
2. **App** (`lib/services/mqtt_service.dart`): `MqttService.baseTopic`
   ersetzt das bisher hart einprogrammierte `'zigbee2mqtt'` in der
   Geräteliste-Subscription UND beim Schalten (`publishZigbeeSwitch`).
   `reconnect()` nimmt jetzt einen `baseTopic`-Parameter an. Für jeden
   bestehenden Account (inkl. Hanfi) bleibt das Verhalten exakt gleich,
   weil überall `zigbee2mqtt` der Default bleibt.
3. **Settings-Bildschirm**: neues Feld "Themen-Namensraum (optional)"
   direkt unter der bestehenden Broker-Konfiguration.
4. Alles verifiziert: `flutter analyze` sauber, `flutter test` 47/47
   grün, `python -m py_compile server.py` sauber, Debug-Build auf dem
   Handy installiert, Live-Verbindung zu Hanfis echtem Broker weiterhin
   bestätigt funktionierend (kein Regressions-Bug), neues Einstellungen-
   Feld sichtbar und korrekt leer für Accounts ohne eigenen Namensraum.

**Was das bedeutet:** Sobald ein Kunden-Pi (ob beim Lieferanten oder auf
deinem eigenen Server) mit einem eigenen Themen-Namensraum UND eigenen
MQTT-Zugangsdaten provisioniert ist, reicht es, diese drei Werte
(Adresse, Zugangsdaten, Namensraum) in den Einstellungen einzutragen -
kein weiterer App- oder Backend-Code nötig.

## Konkrete Mosquitto-Vorlage (für den Lieferanten oder für deinen eigenen Server)

Für JEDEN Kunden ein eigener MQTT-Benutzer, der nur seinen eigenen
Themen-Namensraum lesen/schreiben darf:

```bash
# Einmalig: Passwort-Datei anlegen (erster Nutzer)
mosquitto_passwd -c /etc/mosquitto/passwd kunde_ab12cd34
# Weitere Nutzer ergänzen (ohne -c, sonst wird die Datei überschrieben)
mosquitto_passwd /etc/mosquitto/passwd kunde_ef56gh78
```

`/etc/mosquitto/acl.conf`:

```
# Jeder Kunde darf NUR unter seinem eigenen Namensraum lesen/schreiben.
user kunde_ab12cd34
topic readwrite kunde_ab12cd34/#

user kunde_ef56gh78
topic readwrite kunde_ef56gh78/#
```

`/etc/mosquitto/mosquitto.conf` (relevanter Ausschnitt):

```
allow_anonymous false
password_file /etc/mosquitto/passwd
acl_file /etc/mosquitto/acl.conf
```

Der Kunden-Namensraum (`kunde_ab12cd34` im Beispiel) muss dann auch in
`config/zigbee2mqtt.yaml` auf dem jeweiligen Pi als `mqtt.base_topic`
eingetragen werden (aktuell dort fest `zigbee2mqtt` für alle Geräte -
siehe nächster Abschnitt) und identisch in der App unter "Themen-
Namensraum" bei diesem Kunden-Account.

## Noch offen (bewusst nicht umgesetzt - braucht deine Entscheidung zuerst)

- **Wie wird der Namensraum + die Zugangsdaten pro Pi erzeugt?** Aktuell
  ist `config/zigbee2mqtt.yaml` im Golden Image für alle Geräte
  identisch (`base_topic: zigbee2mqtt`, siehe Datei). Für echte
  Mehrkunden-Isolation müsste `scripts/firstboot.sh` beim ersten Start
  einen zufälligen Namensraum erzeugen (z.B. aus der schon vorhandenen
  `machine-id`) und `zigbee2mqtt.yaml` damit umschreiben, statt einer
  festen Datei. Das hängt direkt an Option A vs. B oben - ich wollte hier
  nicht raten, ob der Lieferant oder du diesen Teil baut/hostet.
- **Automatische Zuordnung Pi ↔ Kunden-Account** - das ist dasselbe
  Thema wie der von dir gewünschte Pi-Onboarding-Flow (WLAN + Kundendaten
  in einem Schritt), noch nicht begonnen, siehe eigener Punkt in
  SALE-READINESS.md.
