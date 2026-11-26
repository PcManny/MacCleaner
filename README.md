# MacCleaner

Ein kostenloser Mac-Aufräumer mit Symbol in der Menüleiste – als einfacher Ersatz für Abo-Programme wie CleanMyMac.
Selbst gebaut, für Familie und Freunde gedacht, für alle freigegeben.

*English summary below.*

## Was MacCleaner kann

- **Menüleiste:** eigenes Symbol; per Klick freier Speicher, Sicherheitsstatus, Arbeitsspeicher und Malware-Status auf einen Blick
- **Aufräumen:** Programm-Caches, Protokolle, Xcode- und Entwickler-Caches, alte Downloads, Mail-Anhänge, iPhone-Backups, Papierkorb leeren
- **Programme entfernen:** App samt Einstellungen, Caches und Hintergrunddiensten – dazu „Reste ohne Programm“ von früher gelöschten Apps
- **Speicherfresser:** Ordnergrößen zum Durchklicken, große Dateien, doppelte Dateien
- **Arbeitsspeicher:** Speicherdruck, größte Verbraucher (mit „Beenden“), Arbeitsspeicher freigeben
- **Sicherheit:** SIP, Gatekeeper, FileVault, Firewall, Freigaben (SSH, Bildschirm, SMB), Profile/Fernverwaltung, Hosts-Datei, Proxy, Autostart mit Signaturprüfung, laufende Programme. Neue Autostart-Einträge werden alle 5 Minuten erkannt und gemeldet.
- **Malware-Suche:** bekannte Werbe- und Schadprogramme, verdächtige Hintergrundprogramme, veränderte (z. B. gecrackte) Programme, Browser-Erweiterungen, Stand von Apples Virenschutz XProtect
- **Wartung:** DNS-Cache, Spotlight, Vorschau-Cache, „Öffnen mit“-Menü, Schriften-Cache, Dock/Finder neu starten

## Grundsätze

- **Nie direkt löschen:** Alles landet zuerst im Papierkorb und lässt sich zurückholen.
- **Nichts Unsicheres vorausgewählt:** Was nicht eindeutig ist, musst du selbst anhaken.
- **Keine Daten ins Internet:** MacCleaner arbeitet nur auf deinem Mac. Kein Konto, keine Werbung, kein Abo.

## Installieren

Voraussetzung: **macOS 15 (Sequoia) oder neuer**, Apple-Chip oder Intel.

1. Unter **Releases** (rechts auf dieser Seite) die Datei `MacCleaner.zip` laden und doppelklicken.
2. `MacCleaner.app` in den Ordner **Programme** ziehen.
3. Die Datei **„Bitte zuerst lesen.html“** öffnen – sie erklärt Schritt für Schritt den ersten Start.

**Warum warnt macOS beim ersten Öffnen?** MacCleaner ist ein kostenloses Hobby-Projekt und nicht bei Apple
gegen Gebühr „beglaubigt“. Beim ersten Start daher: *Systemeinstellungen → Datenschutz & Sicherheit →
„Dennoch öffnen“*. Danach startet die App ganz normal.

Für Aufräumen und Malware-Suche braucht MacCleaner den **Festplattenvollzugriff**
(*Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff*). Die App erklärt das unter Einstellungen.

## Selbst bauen

Braucht Xcode.

```bash
./build.sh --install     # bauen, nach /Applications kopieren und starten
./build.sh --public      # Paket für die Weitergabe: build/MacCleaner.zip
```

Selbsttest, der nichts verändert:

```bash
/Applications/MacCleaner.app/Contents/MacOS/MacCleaner --selftest
```

## Fragen, Fehler, Ideen

Gern unter **Issues** melden. Das ist ein Freizeitprojekt – Antworten können dauern, Verbesserungen sind willkommen.

## Lizenz

MIT – frei nutzbar und veränderbar, ohne Gewähr. Siehe [LICENSE](LICENSE).
Entstanden mit Hilfe von Claude (KI-Assistent von Anthropic).

---

## English summary

MacCleaner is a free, open-source menu bar app for macOS 15+ that cleans caches and old files, uninstalls apps
with their leftovers, finds large and duplicate files, shows memory usage, checks security settings and scans for
known adware/malware, modified (cracked) apps and browser extensions. It never deletes directly (everything goes to
the Trash) and sends no data to the internet. The interface is in German.
Download `MacCleaner.zip` from **Releases**; on first launch allow it under
*System Settings → Privacy & Security → Open Anyway*.
