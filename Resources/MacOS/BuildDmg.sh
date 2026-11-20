#!/bin/bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Verwendung: $0 /Pfad/MailNotesAgent.app /Pfad/Addin /Pfad/Ausgabe.dmg"
  exit 1
fi
SOURCE_APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ADDIN_DIR="$(cd "$2" && pwd)"
OUTPUT_DIR="$(dirname "$3")"
mkdir -p "$OUTPUT_DIR"
OUTPUT="$(cd "$OUTPUT_DIR" && pwd)/$(basename "$3")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -e "$OUTPUT" ]; then
  echo "Fehler: Ausgabedatei existiert bereits: $OUTPUT"
  exit 2
fi
test -x "$SOURCE_APP/Contents/MacOS/MailNotesAgent"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE_APP/Contents/Info.plist")
test "$(/usr/bin/lipo -archs "$SOURCE_APP/Contents/MacOS/MailNotesAgent")" = "arm64"
node "$REPO_DIR/Setup/addin-package.cjs" validate "$ADDIN_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mailnotes-dmg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cp "$REPO_DIR/Data/MailNotes.sqlite" "$WORK_DIR/template.sqlite"
test "$(/usr/bin/sqlite3 -readonly "file:$WORK_DIR/template.sqlite?immutable=1" 'SELECT count(*) FROM Note;')" = "0"
test "$(/usr/bin/sqlite3 -readonly "file:$WORK_DIR/template.sqlite?immutable=1" 'SELECT count(*) FROM Mail;')" = "0"
test "$(/usr/bin/sqlite3 -readonly "file:$WORK_DIR/template.sqlite?immutable=1" 'PRAGMA integrity_check;')" = "ok"

PAYLOAD="$WORK_DIR/MailNotes $VERSION"
mkdir -p "$PAYLOAD"
/usr/bin/ditto --norsrc --noextattr "$SOURCE_APP" "$PAYLOAD/MailNotesAgent.app"
node "$REPO_DIR/Setup/addin-package.cjs" deploy "$ADDIN_DIR" "$PAYLOAD/MailNotesAgent.app/Contents/Resources/Addin"
cp "$REPO_DIR/Data/MailNotes.sqlite" "$PAYLOAD/MailNotesAgent.app/Contents/MacOS/Data/MailNotes.sqlite"
# Auch mit einem älteren Delphi-Bundle immer das App-Symbol mitliefern.
mkdir -p "$PAYLOAD/MailNotesAgent.app/Contents/Resources"
cp "$SCRIPT_DIR/MN-OK.icns" "$PAYLOAD/MailNotesAgent.app/Contents/Resources/MailNotesAgent.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile MailNotesAgent.icns" "$PAYLOAD/MailNotesAgent.app/Contents/Info.plist"
# Das Entwicklungssiegel passt nach dem Paketexport nicht mehr.
# Fuer dieses lokale Testpaket App und Bibliotheken ad hoc versiegeln.
/usr/bin/codesign --force --deep --sign - "$PAYLOAD/MailNotesAgent.app"
/usr/bin/codesign --verify --deep --strict "$PAYLOAD/MailNotesAgent.app"
cp "$SCRIPT_DIR/InstallAgentMac.sh" "$SCRIPT_DIR/de.mailnotes.agent.plist.template" "$PAYLOAD/"

cat > "$PAYLOAD/Installieren.command" <<'STARTER'
#!/bin/bash
set -u
cd "$(dirname "$0")" || exit 1
echo "MailNotes-Paket pruefen ..."
if /usr/bin/shasum -a 256 -c SHA256SUMS.txt; then
  /bin/bash ./InstallAgentMac.sh "$PWD/MailNotesAgent.app"
  result=$?
else
  echo "Fehler: Das Installationspaket ist unvollstaendig oder veraendert."
  result=1
fi
echo
if [ "$result" -eq 0 ]; then
  echo "Fertig. Zum Testen die installierte MailNotesAgent.app im Finder starten."
else
  echo "Installation nicht erfolgreich. Die Fehlermeldung steht oben."
fi
read -r -p "Zum Schliessen die Eingabetaste druecken. " ignored || true
exit "$result"
STARTER
chmod 755 "$PAYLOAD/Installieren.command" "$PAYLOAD/InstallAgentMac.sh"
cat > "$PAYLOAD/Bitte zuerst lesen.txt" <<INFO
MailNotes $VERSION fuer macOS – Apple Silicon

Dieses erste DMG ist fuer den lokalen Test vorgesehen.
Die App ist lokal ad hoc signiert. Das Paket ist nicht notarisiert.
Ein Intel-Mac wird von diesem Paket nicht unterstuetzt.

Installation
1. Einen manuell gestarteten MailNotes-Agenten ueber dessen Menue beenden.
   Outlook kann waehrend der Installation geschlossen bleiben.
2. Installieren.command doppelklicken. Es oeffnet sich ein Terminalfenster.
3. Bei der ersten Einrichtung kann macOS fuer das lokale HTTPS-Zertifikat
   nach einem Administrator-Kennwort fragen.
4. Die installierte App im Finder oeffnen. Danach MailNotes in Outlook neu laden.
5. Das DMG anschliessend auswerfen.

Falls macOS das nicht notarisierte Testpaket blockiert, die angezeigte
Sicherheitsmeldung beachten. Eine Freigabe kann unter Systemeinstellungen,
Datenschutz & Sicherheit erforderlich sein. Bei heruntergeladenen Kopien
kann die Genehmigung je nach macOS-Version auch fuer die App noetig sein.

Das Skript installiert fuer den angemeldeten Benutzer nach
~/Library/Application Support/MailNotes/Agent/MailNotesAgent.app
Der Agent wird in diesem Testpaket manuell gestartet.
Optional kann das Installationsskript mit --autostart aufgerufen werden.
Das Outlook-Add-in wird vom Agenten aus dem App-Bundle uebernommen.

Die persoenliche Datenbank liegt ausserhalb des App-Bundles.
Vor einem Update bitte eine Datenbanksicherung erstellen.
Die Migration ergaenzt das Schema fuer Bilder, Wiedervorlagen und Dateiverknuepfungen auf Version 9.

Der Agent muss https://localhost:48571 erreichen koennen.
Ist Port 48571 durch einen manuell gestarteten Prozess belegt,
bricht die Installation mit einem Hinweis ab.

Ein sporadischer Darstellungsfehler der Markdown-Vorschau ist weiterhin
ungeklaert. Der gespeicherte Rohtext blieb in den bisherigen Faellen korrekt.

Dieses DMG ersetzt nicht die erstmalige Einrichtung des Outlook-Add-ins.
Dafuer kann das Manifest im App-Bundle verwendet werden:
MailNotesAgent.app/Contents/Resources/Addin/manifest.xml
INFO

(
  cd "$PAYLOAD"
  /usr/bin/find . -type f ! -name SHA256SUMS.txt -exec /usr/bin/shasum -a 256 {} \; > "$WORK_DIR/SHA256SUMS.txt"
)
mv "$WORK_DIR/SHA256SUMS.txt" "$PAYLOAD/SHA256SUMS.txt"
/usr/bin/hdiutil create -quiet -volname "MailNotes $VERSION" -srcfolder "$PAYLOAD" -format UDZO "$OUTPUT"
/usr/bin/hdiutil verify "$OUTPUT"
(
  cd "$(dirname "$OUTPUT")"
  /usr/bin/shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256"
)
echo "DMG erstellt: $OUTPUT"
