#!/bin/bash
set -euo pipefail

LABEL="de.mailnotes.agent"
INSTALL_DIR="$HOME/Library/Application Support/MailNotes/Agent"
INSTALL_APP="$INSTALL_DIR/MailNotesAgent.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$LABEL.plist"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_TEMPLATE="$SCRIPT_DIR/de.mailnotes.agent.plist.template"

usage() {
  echo "Verwendung:"
  echo "  $0 /Pfad/zu/MailNotesAgent.app"
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage
fi

SOURCE_APP="${1%/}"

if [ ! -d "$SOURCE_APP" ]; then
  echo "Fehler: App-Bundle nicht gefunden:"
  echo "  $SOURCE_APP"
  exit 2
fi

if [ ! -x "$SOURCE_APP/Contents/MacOS/MailNotesAgent" ]; then
  echo "Fehler: MailNotesAgent ist im App-Bundle nicht ausführbar:"
  echo "  $SOURCE_APP/Contents/MacOS/MailNotesAgent"
  exit 3
fi

if [ ! -f "$PLIST_TEMPLATE" ]; then
  echo "Fehler: plist-Vorlage nicht gefunden:"
  echo "  $PLIST_TEMPLATE"
  exit 4
fi

echo "MailNotesAgent für macOS installieren"
echo

# Bereits geladenen LaunchAgent sauber entladen.
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "Vorhandenen LaunchAgent stoppen ..."
  launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
fi

echo "Installationsverzeichnisse anlegen ..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$HOME/Library/Logs"

echo "MailNotesAgent.app installieren ..."
rm -rf "$INSTALL_APP"
/usr/bin/ditto "$SOURCE_APP" "$INSTALL_APP"

echo "LaunchAgent-Konfiguration erzeugen ..."
ESCAPED_HOME=$(printf '%s\n' "$HOME" | sed 's/[&|]/\\&/g')
sed "s|@@HOME@@|$ESCAPED_HOME|g" "$PLIST_TEMPLATE" > "$PLIST_TARGET"

echo "plist prüfen ..."
plutil -lint "$PLIST_TARGET"

echo "LaunchAgent laden ..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"

sleep 1

echo
echo "Status:"
if pgrep -fl MailNotesAgent >/dev/null 2>&1; then
  pgrep -fl MailNotesAgent
else
  echo "WARNUNG: MailNotesAgent-Prozess wurde nicht gefunden."
fi

echo
if curl --silent --fail --max-time 3 http://127.0.0.1:48571/ping; then
  echo
  echo "MailNotesAgent wurde erfolgreich installiert und gestartet."
else
  echo
  echo "WARNUNG: MailNotesAgent antwortet noch nicht auf Port 48571."
  echo "Fehlerprotokoll:"
  echo "  $HOME/Library/Logs/MailNotesAgent-error.log"
  exit 5
fi
