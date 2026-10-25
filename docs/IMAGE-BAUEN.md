# Kunden-Image bauen, verkleinern und prüfen (Stand 2026-10-25)

Ablauf, mit dem das Beta-Image `LittleFarmers-OS-Beta-2026-10-25.img(.gz)` entstanden ist.
Das Ergebnis liegt auf dem PC unter `D:\LF-Images` (bewusst **nicht** in OneDrive, 12 bis 31 GB).

1. **Standard-Pi-OS** (Trixie, 64-bit) mit dem Raspberry Pi Imager auf eine gute Marken-SD-Karte schreiben.
   Bei der Anpassung: Hostname, Benutzer `littlefarmers`, WLAN (nur für die Installation), SSH **nur mit Schlüssel**, Raspberry Pi Connect **aus**.
2. Dateien per `tar`/`scp` auf den Pi, `./install.sh` (ohne `sudo`), neu starten, Selbst-Update abwarten (ca. 2 Minuten ohne Fehler).
3. Wenn alles läuft und das Repo dem GitHub-Stand entspricht (`git status` sauber): `./build-image.sh --yes`.
   Das Skript räumt WLAN, Zigbee-Netz, Schlüssel, Geräte-ID, cloud-init-Daten, netplan-Dateien und den Passwort-Hash auf und fährt den Pi herunter.
4. SD-Karte am PC komplett als `.img` auslesen: `Tools/sd-karte-auslesen.ps1` (Rechtsklick, Mit PowerShell ausführen; liest nur, setzt sich selbst als Administrator).
5. Verkleinern (WSL, Linux von Docker Desktop): `Tools/image-verkleinern.sh` (arbeitet an einer Kopie, Ergebnis ca. 12 GB, danach `.gz` ca. 1,4 GB).
6. **Prüfen und bereinigen:** `Tools/image-pruefen.sh` (nur lesen) und `Tools/image-bereinigen.sh`. Es darf kein WLAN-Name, kein Passwort-Hash und kein Entwickler-Hostname mehr im Image stehen.
7. Test: Image mit dem Imager schreiben, **ohne Anpassung**; Pi **ohne Kabel und ohne WLAN** starten; nach 2 bis 3 Minuten findet die App ihn per Bluetooth (Einstellungen > Gerät einrichten).

## Bekannte Stolpersteine
- Imager schreibt WLAN-Daten als netplan-Datei `/etc/netplan/90-NM-*.yaml`; die muss ins Aufräumen.
- Ein schwacher SD-Karten-Block zerstört die Startpartition (cmdline.txt, config.txt, initramfs8). Nur Marken-Karten verwenden und nach dem Schreiben verifizieren lassen.
- Kartenleser lassen sich nicht per `wsl --mount` einbinden; deshalb zuerst als Datei auslesen und dann die Datei per Loop-Gerät öffnen.
- Zigbee-Stick: Ein Stick hält genau ein Netz. Nie den Stick eines laufenden Pi an einen anderen Pi stecken (das neue Netz überschreibt das alte).
- Das verkleinerte Image hat keine automatische Erweiterung des Systems auf die ganze Karte (Root ca. 11 GB, Rest frei).
