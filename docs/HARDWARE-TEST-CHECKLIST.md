# Checkliste: erster Test an echter Pi-Hardware

Erstellt 2026-08-16, autonom vorbereitet. Der komplette Onboarding-Flow
(WLAN-Einrichtung, Kopplungscode, automatische Broker-Zuordnung) ist
fertig programmiert und gegen das Backend getestet, aber **noch nie an
einem echten, physisch bootenden Pi ausprobiert.** Diese Liste ist für
den ersten Durchlauf gedacht - Schritt für Schritt, damit klar ist, wo
es hakt, falls es hakt.

## Vorbereitung

- [ ] Golden Image auf eine SD-Karte flashen (aktueller Stand von
      GitHub, `main`-Branch, Commit `b90dff7` oder neuer)
- [ ] Ein Testkonto in der App bereithalten (nicht dein Hauptkonto)
- [ ] Handy mit installierter App griffbereit
- [ ] Zugriff auf ein zweites WLAN-Gerät (Laptop/Handy), um den
      Einrichtungs-Hotspot von außen zu sehen

## Schritt 1: Erststart / Hotspot

- [ ] Pi mit SD-Karte einschalten, ohne vorher ein WLAN einzurichten
- [ ] Prüfen: taucht ein WLAN-Netzwerk namens **"LittleFarmers"** auf?
- [ ] Prüfen: verlangt es ein Passwort? (sollte **nicht** offen sein -
      das war der Hotspot-Fix von heute Nacht)
- [ ] Mit dem Hotspot verbinden, prüfen ob eine Einrichtungsseite
      erscheint (captive portal)
- [ ] Echtes Heim-WLAN dort eintragen

## Schritt 2: Erststart-Absicherung

- [ ] Nach dem ersten Boot prüfen: hat jedes Gerät ein **eigenes**
      zufälliges System-Passwort? (`/var/lib/littlefarmers/initial-password`,
      nur per direktem Zugriff aufs Gerät einsehbar - falls du zwei
      Geräte testest, vergleichen, dass die Passwörter unterschiedlich sind)

## Schritt 3: Kopplungscode

- [ ] Nach erfolgreicher Internetverbindung: taucht irgendwo am Gerät
      (Aufkleber/Display, je nachdem was ihr für die Serienfertigung
      vorseht) ein Kopplungscode auf?
- [ ] Falls (noch) kein Aufkleber vorhanden: Code direkt auf dem Gerät
      auslesen (`cat /etc/littlefarmers/device-code`) und manuell in die
      App eintragen

## Schritt 4: Kopplung in der App

- [ ] Mit Testkonto einloggen, Kopplungscode eingeben
- [ ] Prüfen: bekommt das Gerät innerhalb weniger Sekunden (Polling-
      Intervall, Standard 5s) die Zugangsdaten und verbindet sich zum
      Broker?
- [ ] In der App: taucht ein Zigbee-Gerät (falls eines angelernt ist)
      oder zumindest eine leere, aber funktionierende Geräteliste auf?

## Schritt 5: Web-UI-Absicherung prüfen (heutiger Fix)

- [ ] Vom zweiten WLAN-Gerät aus versuchen, `http://<Pi-IP>:8080`
      aufzurufen - sollte **nicht** erreichbar sein (war vorher offen,
      heute Nacht auf localhost beschränkt)

## Schritt 6: Zigbee-Gerät anlernen (falls Hardware vorhanden)

- [ ] Ein echtes Zigbee-Gerät (Licht, Steckdose, Sensor) anlernen
- [ ] Prüfen: taucht es in der App auf, lässt sich schalten/auslesen?

## Was NICHT getestet werden muss (schon live verifiziert)

- Broker-Provisionierung selbst (Backend legt automatisch MQTT-Zugang
  an) - das wurde heute Nacht schon end-to-end gegen den echten Server
  getestet, nur eben ohne echten Pi dazwischen.
- Backend-Sicherheitsfixes (Rate-Limiting, Session-Ablauf etc.) - live
  auf dem Server, unabhängig von der Pi-Hardware.

## Falls etwas nicht funktioniert

Kurz notieren: welcher Schritt, welche Fehlermeldung/welches Verhalten
- dann einfach den nächsten Chat mit mir starten und schildern, das
lässt sich meistens schnell eingrenzen (Logs: `journalctl -u
littlefarmers-pair-device -u zigbee2mqtt -u littlefarmers-wifi-fallback
--no-pager`).
