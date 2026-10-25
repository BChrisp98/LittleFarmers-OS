# Little Farmers – Kurzanleitung für Beta-Tester (Entwurf, Stand 2026-10-24)

Willkommen! Mit Little Farmers steuert deine App Licht, Lüfter und Bewässerung deiner Pflanzen automatisch und zeigt dir Temperatur, Luftfeuchtigkeit und Bodenfeuchtigkeit. Die Steuerung läuft auf unserem Server und dem kleinen Computer (Raspberry Pi) bei dir zu Hause, auch wenn die App geschlossen ist.

> **Stand:** Beta-Anleitung. Sie wird nach dem ersten Test mit einem frischen Pi und einem fremden Handy noch einmal an die echten Bildschirmtexte angepasst.

## Das brauchst du
- **Android-Handy** (die Little-Farmers-App bekommst du als Datei, siehe Schritt 1)
- **Raspberry Pi** (empfohlen: Pi 4 oder Pi 5, mit eingebautem WLAN und Bluetooth), Netzteil und eine **SD-Karte mit mindestens 16 GB**
- **Zigbee-USB-Stick** am Pi, den Zigbee2MQTT unterstützt (zum Beispiel Sonoff ZBDongle-E oder ZBDongle-P)
- **Zigbee-Geräte:** Temperatur-/Luftfeuchtigkeitssensor (zum Beispiel Sonoff SNZB-02), Bodenfeuchtigkeitssensor und Funksteckdosen für Licht, Lüfter und Pumpe
- **WLAN** zu Hause (2,4 GHz) und Strom in der Nähe der Pflanzen

Du brauchst nicht alles: Nur eine Pumpe, nur eine Lampe oder nur Sensoren gehen auch. Ohne Geräte nutzt du die App als Pflanzen-Tagebuch mit Community.

## Schritt 1: App installieren und Konto anlegen
1. Du bekommst von Christoph die App-Datei (`little-farmers-….apk`). Auf dem Handy öffnen. Android fragt, ob du Apps aus dieser Quelle zulassen willst: **Zulassen**, dann **Installieren**.
2. App öffnen, **Registrieren** mit deiner E-Mail-Adresse und einem Passwort (mindestens 8 Zeichen).
3. Dein Konto muss von Christoph **freigeschaltet** werden. Sag ihm kurz Bescheid, dann geht es meist innerhalb von Minuten.

## Schritt 2: Raspberry Pi vorbereiten und verbinden
**Einmalig, am Computer:** Lade das Little-Farmers-Abbild herunter (Link bekommst du von Christoph) und schreibe es mit dem kostenlosen Programm **Raspberry Pi Imager** auf die SD-Karte: *Betriebssystem wählen → Eigenes Image verwenden → die heruntergeladene Datei → SD-Karte wählen → Schreiben*. Das dauert etwa 10 Minuten.

1. SD-Karte in den Pi stecken, **Zigbee-Stick** anstecken, Netzteil anschließen. Nach etwa **2 Minuten** ist der Pi bereit.
2. In der App: **Einstellungen → Gerät einrichten** (Bluetooth). Bluetooth am Handy einschalten, den Pi in der Liste wählen, dein **WLAN** auswählen und das Passwort eingeben (oder den WLAN-QR-Code deines Routers scannen).
3. Der Pi verbindet sich mit deinem WLAN und mit deinem Konto. Das dauert etwa eine Minute. Danach zeigt die App "Fertig".
4. **Falls Bluetooth nicht klappt:** Der Pi öffnet ein eigenes WLAN namens **LittleFarmers** (Passwort **LittleFarmers2026!**). Verbinde dich damit, wähle auf der Seite, die sich öffnet, dein Heim-WLAN und gib das Passwort ein. Wenn die App danach den Pi nicht von selbst findet, schreib uns über **Einstellungen → Support**, wir helfen dir beim Koppeln.

## Schritt 3: Sensoren und Steckdosen anlernen
1. Öffne in der App **Einstellungen → Geräte-Übersicht** und tippe auf **Neues Gerät koppeln**. Der Pi sucht jetzt etwa **4 Minuten** lang nach neuen Geräten.
2. Versetze dein Zigbee-Gerät in den Anlernmodus (bei den meisten Sensoren und Steckdosen die Taste etwa **5 Sekunden** gedrückt halten, bis die LED blinkt; bei Steckdosen oft kurz ein- und ausstecken).
3. Sobald das Gerät erscheint, fragt die App nach einem **Namen** (zum Beispiel "Lampe Zelt"). Vergib einen kurzen Namen, damit du die Geräte später leicht erkennst.
4. Wiederhole das für jedes Gerät. In der Geräte-Übersicht siehst du alle Geräte mit dem Status **online**.

## Schritt 4: Pflanze anlegen
1. Startseite → **+** → **Neue Pflanze**.
2. Name, Pflanzenart und Wachstumsphase wählen. Tipp: In der **Community** gibt es fertige Setups (zum Beispiel Basilikum, Tomate, Alocasia). Mit **Übernehmen** füllt die App Licht-Zeiten, Temperaturen und Bewässerung für dich aus.
3. **Geräte zuordnen:** Wähle Sensoren und Steckdosen für diese Pflanze. Alles ist **optional**, was du nicht hast, lässt du leer.
4. Fertig. Die Automatik läuft sofort auf dem Server.

## So benutzt du die App
- **Automatik oder manuell:** Bei jedem Gerät (Licht, Lüfter, Pumpe) gibt es einen Schalter. **Automatik** heißt: der Server regelt nach deinen Werten. Schaltest du manuell, bleibt das so, bis du wieder auf Automatik stellst.
- **Diagramme:** Tippe auf das Symbol rechts oben im Diagramm für die Vollbildansicht. Du kannst ziehen und zoomen. Blaue Balken zeigen Bewässerungen, gelbe Balken Lüfterläufe.
- **Werte anpassen:** Bei der Pflanze unter **Phase & Automatik** stellst du Licht-Zeiten, Temperatur-, Luftfeuchtigkeits- und Bodenwerte ein. Der Lüfter kann auch nach Luftfeuchtigkeit schalten.
- **KI-Assistent:** Frag den Assistenten (Reiter **KI**) oder lass ein Foto analysieren. Die Antworten sind Hinweise, keine Fachberatung.
- **Warnungen:** Wenn dein Pi offline geht, bekommst du eine Mail und eine Nachricht aufs Handy.

## Wenn etwas nicht klappt
- **Sensor zeigt keinen Wert:** Die meisten Zigbee-Sensoren melden sich nur etwa einmal pro Stunde. Prüfe Batterie und Abstand zum Pi.
- **Licht, Lüfter oder Pumpe reagieren nicht:** In der Geräte-Übersicht prüfen, ob die Steckdose "online" ist, und ob der Schalter auf **Automatik** steht.
- **Pi bleibt offline:** WLAN prüfen, Pi kurz vom Strom nehmen und wieder anstecken.
- **Anderes:** Schreib uns. In der App unter **Einstellungen → Support** (WhatsApp oder E-Mail).

## Wichtig für deine Sicherheit
- **Automatik ist eine Hilfe, kein Ersatz für Aufsicht.** Schau regelmäßig nach deinen Pflanzen und Geräten. Nutze nur geprüfte Steckdosen und halte Wasser und Strom getrennt.
- Little Farmers ist in der **Beta**: Es kann Fehler geben. Bitte melde alles, was dir auffällt.
- Du kannst dein Konto jederzeit selbst löschen (**Einstellungen → Konto löschen**).
