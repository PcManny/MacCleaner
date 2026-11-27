# MacCleaner

Ein kostenloser Mac-Aufräumer mit Symbol in der Menüleiste – anstelle einer Abo-App.
Selbst gebaut, für Familie und Freunde gedacht, für alle freigegeben.

*English summary below.*

## Was MacCleaner kann

- **Menüleiste:** eigenes Symbol; per Klick freier Speicher, Sicherheitsstatus, Arbeitsspeicher und Malware-Status auf einen Blick
- **Aufräumen:** Programm-Caches, Protokolle, Xcode- und Entwickler-Caches, alte Downloads, Mail-Anhänge, iPhone-Backups, Papierkorb leeren
- **Programme entfernen:** eine oder mehrere Apps auf einmal samt Einstellungen, Caches und Hintergrunddiensten – dazu „Reste ohne Programm“ von früher gelöschten Apps
- **Speicherfresser:** Ordnergrößen zum Durchklicken, große Dateien, doppelte Dateien
- **Arbeitsspeicher:** Speicherdruck, größte Verbraucher (mit „Beenden“), Arbeitsspeicher freigeben
- **Sicherheit:** SIP, Gatekeeper, FileVault, Firewall, Freigaben (SSH, Bildschirm, SMB), Profile/Fernverwaltung, Hosts-Datei, Proxy, Autostart mit Signaturprüfung, laufende Programme. Neue Autostart-Einträge werden alle 5 Minuten erkannt und gemeldet.
- **Malware-Suche:** bekannte Werbe- und Schadprogramme, verdächtige Hintergrundprogramme, veränderte (z. B. gecrackte) Programme, Browser-Erweiterungen, Stand von Apples Virenschutz XProtect
- **Meine Tools:** alle Werkzeuge als Kacheln mit Suche – u. a. Duplikatscanner, Downloads, Papierkorb, KI-Müll (Caches und Modelle von KI-Programmen), Time-Machine-Schnappschüsse, Programm-Berechtigungen (wer darf Kamera, Mikrofon, alle Dateien …), Hintergrundobjekte und ein Putzmodus für Bildschirm und Tastatur
- **Übersicht:** Rundum-Check (Aufräumen, Sicherheit und Malware auf einen Klick) und „Alles aufräumen“ für die sicheren Kategorien
- **Wartung:** DNS-Cache, Spotlight, Vorschau-Cache, „Öffnen mit“-Menü, Schriften-Cache, Dock/Finder neu starten

## Grundsätze

- **Nie direkt löschen:** Alles landet zuerst im Papierkorb und lässt sich zurückholen.
- **Nichts Unsicheres vorausgewählt:** Was nicht eindeutig ist, musst du selbst anhaken.
- **Keine Daten ins Internet:** MacCleaner arbeitet nur auf deinem Mac. Kein Konto, keine Werbung, kein Abo.

## Installieren

Voraussetzung: **macOS 15 (Sequoia) oder neuer**, Apple-Chip oder Intel.

1. Unter **Releases** (rechts auf dieser Seite) **`MacCleaner.dmg`** laden und doppelklicken.
2. Im Fenster, das sich öffnet, `MacCleaner` auf den Ordner **Programme** ziehen.
3. MacCleaner aus dem Ordner Programme starten und beim Hinweis auf **„Öffnen“** klicken.

Alternativ gibt es `MacCleaner.zip` (praktisch zum Weiterschicken, z. B. per Messenger): doppelklicken,
`MacCleaner.app` in **Programme** ziehen. Die beiliegende **„Bitte zuerst lesen.html“** erklärt alles Schritt für Schritt.

Die App ist mit einer Apple-Developer-ID signiert und bei Apple beglaubigt (notarisiert). macOS fragt beim
ersten Start deshalb nur kurz nach, ob du sie öffnen willst.

Für Aufräumen und Malware-Suche braucht MacCleaner den **Festplattenvollzugriff**
(*Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff*). Die App erklärt das unter Einstellungen.

## Selbst bauen

Braucht Xcode.

```bash
./build.sh --install     # bauen, nach /Applications kopieren und starten
./build.sh --public      # Weitergabe: build/MacCleaner.zip und build/MacCleaner.dmg (signiert + beglaubigt, wenn Developer ID vorhanden)
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
known adware/malware, modified (cracked) apps and browser extensions. "Meine Tools" collects all tools as tiles,
including Time Machine local snapshots, AI-app junk, app permissions and a screen-cleaning mode. It never deletes
directly (everything goes to the Trash) and sends no data to the internet. The interface is in German.
Download `MacCleaner.dmg` (or `MacCleaner.zip`) from **Releases** and drag the app to Applications.
The app is signed with a Developer ID and notarized.
