# Pi-Onboarding: WLAN + Kundendaten - Konzeptvorschlag

Stand 2026-08-10, geschrieben während Christophs Abwesenheit als
Diskussionsgrundlage. **Kein Code dazu geschrieben** - das braucht
erst deine Freigabe des Ablaufs, wie besprochen. Baut direkt auf
`BROKER-SECURITY-PLAN.md` auf (der dort vorgeschlagene Themen-
Namensraum pro Kunde ist Voraussetzung dafür, dass "automatische
Zuordnung" hier überhaupt etwas Sinnvolles bedeutet).

## Was heute schon da ist

- WLAN-Einrichtung funktioniert bereits eigenständig: `wifi-connect`
  (fremdes Open-Source-Tool von Balena) startet einen offenen Hotspot
  `LittleFarmers`, der Kunde verbindet sich, wählt sein WLAN, gibt das
  Passwort ein - fertig. Reine WLAN-Zugangsdaten, keine Konto-Felder.
- Danach läuft Zigbee2MQTT mit einer für JEDES Gerät identischen,
  fest einprogrammierten Konfiguration (`config/zigbee2mqtt.yaml`,
  `config/system.conf`) - kein Bezug zu einem Kundenkonto.
- Die App braucht heute manuelle Eingabe von Broker-Adresse/
  Zugangsdaten/Namensraum in den Einstellungen (siehe
  `BROKER-SECURITY-PLAN.md`) - niemand tippt das freiwillig ab, das
  ist ein reiner Notbehelf für uns beim Testen, kein Kundenerlebnis.

## Die eigentliche Frage: "ein Schritt" oder "zwei Schritte, die sich wie einer anfühlen"

`wifi-connect` ist ein fertiges Fremd-Tool, das nur WLAN-Felder kennt.
Es um Konto-Felder zu erweitern heißt entweder es zu forken (eigene
Version pflegen) oder ein komplett eigenes Captive-Portal zu bauen.
Beides ist möglich, aber deutlich mehr Aufwand/Wartungslast als die
Alternative unten - deshalb hier zwei Optionen zur Wahl:

### Option A (empfohlen): Gerät koppeln nach dem WLAN-Schritt, über die App

1. WLAN-Einrichtung bleibt genau wie heute (`wifi-connect`
   unverändert) - der Kunde verbindet sein Gerät mit dem Internet.
2. Auf jedem Gerät liegt ab Werk ein eindeutiger **Kopplungscode**
   (z.B. aus der schon vorhandenen `machine-id` abgeleitet, oder ein
   separat generierter kurzer Code) - aufgedruckt als QR-Code/Klartext
   auf einem Aufkleber am Gerät (wie bei Chromecast, Sonos, etc.).
3. Sobald das Gerät online ist, meldet es sich beim Backend mit
   diesem Code und wartet (Polling, z.B. alle 5s) auf Zuordnung zu
   einem Konto.
4. Der Kunde öffnet die App, loggt sich ein, tippt "Neues Gerät
   koppeln" und scannt den QR-Code (oder tippt ihn ein).
5. Backend verknüpft Gerät ↔ Konto, erzeugt den MQTT-Benutzer +
   Themen-Namensraum für dieses Konto (falls noch nicht vorhanden) und
   beantwortet die nächste Polling-Anfrage des Geräts mit diesen
   Zugangsdaten.
6. Das Gerät schreibt `zigbee2mqtt.yaml` neu und startet Zigbee2MQTT
   mit den eigenen Zugangsdaten neu.

**Vorteil:** `wifi-connect` bleibt unangetastet (wenig Wartungsaufwand,
kein Fork eines fremden Projekts), der Ablauf ist aus Kundensicht
trotzdem ein einziger, zusammenhängender "Auspacken → Verbinden →
Fertig"-Vorgang, auch wenn es technisch zwei Phasen sind. Genau dieses
Muster (Code auf dem Gerät, koppeln über die schon installierte App)
ist bei Chromecast, Sonos, Philips Hue usw. Standard - Kunden sind das
gewohnt.

**Nachteil:** Der Kunde muss die App tatsächlich installiert und ein
Konto haben, BEVOR er koppeln kann - das ist bei einem Abo-Produkt
wie diesem aber ohnehin der Fall.

### Option B: eigenes Captive Portal mit WLAN- + Konto-Feldern zusammen

`wifi-connect` durch ein eigenes kleines Webformular ersetzen (WLAN-
Auswahl + E-Mail/Passwort-Felder auf derselben Seite), das nach dem
Absenden beides in einem Rutsch erledigt: WLAN verbinden UND das
Gerät sofort dem eingegebenen Konto zuordnen.

**Vorteil:** Wirklich nur EIN Schritt, keine zweite App-Interaktion
nötig, funktioniert auch falls der Kunde die App noch gar nicht
installiert hat.

**Nachteil:** Deutlich mehr Aufwand (eigenes Webportal statt fertigem
Tool), Sicherheitsfrage: Passwort-Eingabe über eine unverschlüsselte
Verbindung zum offenen Hotspot ist grundsätzlich riskanter als über
die schon bestehende, https-abgesicherte App/Backend-Verbindung -
müsste sorgfältig gelöst werden (z.B. TLS auf dem Captive Portal
selbst, was auf einem frisch ausgepackten Gerät ohne bekannten
Hostnamen/Zertifikat nicht trivial ist).

## Meine Einschätzung

Option A ist der pragmatischere erste Schritt - weniger Risiko, nutzt
bestehende, bewährte Bausteine (wifi-connect bleibt, das schon
vorbereitete Themen-Namensraum-Feld aus `BROKER-SECURITY-PLAN.md` wird
direkt gebraucht), und ist ein Muster, das Kunden aus anderen Smart-
Home-Produkten kennen. Option B fühlt sich zwar "in einem Schritt"
an, bringt aber spürbar mehr Aufwand und eine echte Sicherheitsfrage
mit, die zuerst gelöst werden müsste.

**Das ist aber deine Entscheidung** - sag Bescheid, welche Richtung
(oder eine dritte Idee), dann fange ich mit der konkreten Umsetzung
an (Backend-Endpoint für Pairing, App-Screen "Gerät koppeln",
Pi-seitiges Polling-Skript).

## Was für Option A konkret zu bauen wäre (nur zur Einordnung des Aufwands, noch nicht begonnen)

- Backend: `devices`-Tabelle (Kopplungscode, Status, verknüpftes
  Konto), Endpoints `POST /api/devices/claim` (App ruft das beim
  Scannen auf) und `GET /api/devices/<code>/status` (Pi pollt das).
- Pi: neues Skript/systemd-Service, das nach erfolgreicher
  WLAN-Verbindung startet, den eigenen Code an den Endpoint schickt,
  pollt, und bei Erfolg `zigbee2mqtt.yaml`/`system.conf` mit den
  gelieferten Werten überschreibt und den Zigbee2MQTT-Dienst neu
  startet.
- App: neuer Screen "Gerät koppeln" (QR-Scanner oder Code-Eingabe),
  ruft `claim` auf.
- Aufkleber-Generierung für die Produktion (Kopplungscode + QR pro
  Gerät) - das ist ein Prozess-/Logistik-Thema, keine reine
  Software-Frage.
