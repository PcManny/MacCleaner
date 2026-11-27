#!/bin/bash
# Baut MacCleaner.app. Mit --install wird die App nach /Applications kopiert und gestartet.
set -euo pipefail
cd "$(dirname "$0")"

# Xcodes Compiler nutzen, falls vorhanden (die Command Line Tools allein reichen für SwiftUI nicht).
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Universal: läuft auf Apple-Chip und Intel-Macs.
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacCleaner"
APP="build/MacCleaner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/BitteZuerstLesen.html "$APP/Contents/Resources/"
# Private Version (für Familie & Freunde): Kontakt mit Name und E-Mail einbauen.
# Die Datei Resources/Kontakt-privat.plist wird nicht auf GitHub hochgeladen.
if [[ "${1:-}" != "--public" && -f Resources/Kontakt-privat.plist ]]; then
    cp Resources/Kontakt-privat.plist "$APP/Contents/Resources/Kontakt.plist"
    NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" Resources/Kontakt-privat.plist)
    EMAIL=$(/usr/libexec/PlistBuddy -c "Print :Email" Resources/Kontakt-privat.plist)
    export LINE="<p>Schreib einfach eine E-Mail an $NAME: <a href=\"mailto:$EMAIL?subject=MacCleaner\">$EMAIL</a></p>"
    perl -0pi -e 's#<!--KONTAKT-->.*?<!--/KONTAKT-->#$ENV{LINE}#s' "$APP/Contents/Resources/BitteZuerstLesen.html"
    echo "Private Version mit Kontakt $NAME"
fi
# Mit dem Xcode-Entwicklerzertifikat signieren, damit macOS erteilte Berechtigungen
# (z. B. Festplattenvollzugriff) nach einem Neubau behält. Ohne Zertifikat: ad-hoc.
# --public: mit dem „Developer ID Application“-Zertifikat (bezahltes Apple-Konto) unterschreiben
# und von Apple beglaubigen lassen (Notarisierung) – dann startet die App ohne Warnung.
# Ohne dieses Zertifikat: ad-hoc wie früher. Dazu ein ZIP für GitHub (App + Anleitung) in build/.
NOTARY_PROFILE="MacCleaner-Notar"   # angelegt mit: xcrun notarytool store-credentials
if [[ "${1:-}" == "--public" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')
    IDENTITY="${IDENTITY:--}"
else
    IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
fi
if [[ "${IDENTITY:--}" == "-" ]]; then
    codesign --force --options runtime --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Fertig: $APP"

if [[ "${1:-}" == "--public" ]]; then
    STAGE="build/zip/MacCleaner"
    rm -rf build/zip build/MacCleaner.zip
    if [[ "$IDENTITY" != "-" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "Wird bei Apple beglaubigt (dauert meist 1–5 Minuten) …"
        ditto -c -k --keepParent "$APP" build/notar.zip
        xcrun notarytool submit build/notar.zip --keychain-profile "$NOTARY_PROFILE" --wait | tee build/notar.log
        rm -f build/notar.zip
        grep -q "status: Accepted" build/notar.log || { echo "Beglaubigung fehlgeschlagen – siehe build/notar.log"; exit 1; }
        xcrun stapler staple "$APP"
        spctl -a -vv -t exec "$APP"
    else
        echo "Hinweis: ohne Beglaubigung (kein Developer-ID-Zertifikat oder kein Notar-Profil)."
    fi
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    cp Resources/BitteZuerstLesen.html "$STAGE/Bitte zuerst lesen.html"
    ditto -c -k --sequesterRsrc --keepParent "$STAGE" build/MacCleaner.zip
    NOTARY_PROFILE="$NOTARY_PROFILE" Tools/make_dmg.sh "$APP" build/MacCleaner.dmg Resources/dmg-background.png "$STAGE/Bitte zuerst lesen.html"
    rm -rf build/zip
    echo "Öffentliche Pakete: build/MacCleaner.zip und build/MacCleaner.dmg"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MacCleaner || true
    sleep 1
    rm -rf /Applications/MacCleaner.app
    cp -R "$APP" /Applications/
    open /Applications/MacCleaner.app
    echo "Installiert in /Applications und gestartet."
fi
