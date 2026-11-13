#!/bin/bash
set -euo pipefail

LABEL="de.mailnotes.agent"
INSTALL_DIR="$HOME/Library/Application Support/MailNotes/Agent"
INSTALL_APP="$INSTALL_DIR/MailNotesAgent.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_TARGET="$LAUNCH_AGENTS_DIR/$LABEL.plist"

TLS_DIR="$HOME/Library/Application Support/MailNotes/TLS"
TLS_CA="$TLS_DIR/mailnotes-ca.crt"
TLS_CERT="$TLS_DIR/localhost-cert.pem"
TLS_KEY="$TLS_DIR/localhost-key.pem"

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

if [ ! -f "$SOURCE_APP/Contents/Resources/Addin/addin-build.json" ]; then
  echo "Fehler: Das App-Bundle enthaelt kein geprueftes Add-in-Buildmanifest."
  exit 4
fi

# Die ausgelieferte App muss vor jeder Aenderung vollstaendig versiegelt sein.
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
EXPECTED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE_APP/Contents/Info.plist")

tls_pair_matches() {
  local cert_modulus
  local key_modulus

  cert_modulus=$(/usr/bin/openssl x509 -in "$TLS_CERT" -noout -modulus 2>/dev/null || true)
  key_modulus=$(/usr/bin/openssl rsa -in "$TLS_KEY" -noout -modulus 2>/dev/null || true)

  [ -n "$cert_modulus" ] && [ "$cert_modulus" = "$key_modulus" ]
}

tls_is_ready() {
  [ -f "$TLS_CA" ] || return 1
  [ -f "$TLS_CERT" ] || return 1
  [ -f "$TLS_KEY" ] || return 1

  # Nicht mit einem Zertifikat weiterarbeiten, das in den nächsten 30 Tagen abläuft.
  /usr/bin/openssl x509 -in "$TLS_CERT" -noout -checkend 2592000 >/dev/null 2>&1 || return 1
  tls_pair_matches || return 1

  # Zertifikat muss von der gespeicherten MailNotes-CA signiert worden sein.
  /usr/bin/openssl verify -CAfile "$TLS_CA" "$TLS_CERT" >/dev/null 2>&1 || return 1

  # macOS muss der vollständigen Kette für https://localhost vertrauen.
  /usr/bin/security verify-cert -c "$TLS_CERT" -p ssl -s localhost >/dev/null 2>&1 || return 1

  return 0
}

remove_old_trusted_ca() {
  local ca_fingerprints
  local ca_fingerprint

  ca_fingerprints=$(/usr/bin/security find-certificate -a -Z -c "MailNotes Local CA" \
    /Library/Keychains/System.keychain 2>/dev/null \
    | /usr/bin/sed -n 's/^[[:space:]]*SHA-1 hash: //p' || true)

  [ -n "$ca_fingerprints" ] || return 0

  echo "Alte MailNotes-CA aus dem System-Schlüsselbund entfernen ..."
  echo "macOS fragt hierfür ggf. nach dem Administrator-Kennwort."

  while IFS= read -r ca_fingerprint; do
    [ -n "$ca_fingerprint" ] || continue
    sudo /usr/bin/security delete-certificate \
      -Z "$ca_fingerprint" \
      /Library/Keychains/System.keychain
  done <<< "$ca_fingerprints"
}

create_tls_material() {
  local tmp_dir

  remove_old_trusted_ca

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  echo "Lokale MailNotes-CA erzeugen ..."
  /usr/bin/openssl genrsa -out "$tmp_dir/mailnotes-ca.key" 2048

  /usr/bin/openssl req -x509 -new -sha256 \
    -key "$tmp_dir/mailnotes-ca.key" \
    -days 3650 \
    -subj "/CN=MailNotes Local CA/O=MailNotes" \
    -out "$tmp_dir/mailnotes-ca.crt"

  echo "TLS-Zertifikat für localhost erzeugen ..."
  /usr/bin/openssl genrsa -out "$tmp_dir/localhost-key.pem" 2048

  /usr/bin/openssl req -new -sha256 \
    -key "$tmp_dir/localhost-key.pem" \
    -subj "/CN=localhost/O=MailNotes" \
    -out "$tmp_dir/localhost.csr"

  cat > "$tmp_dir/localhost.ext" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1
EOF

  /usr/bin/openssl x509 -req \
    -in "$tmp_dir/localhost.csr" \
    -CA "$tmp_dir/mailnotes-ca.crt" \
    -CAkey "$tmp_dir/mailnotes-ca.key" \
    -CAcreateserial \
    -days 825 \
    -sha256 \
    -extfile "$tmp_dir/localhost.ext" \
    -out "$tmp_dir/localhost-cert.pem"

  /usr/bin/ditto "$tmp_dir/mailnotes-ca.crt" "$TLS_CA"
  /usr/bin/ditto "$tmp_dir/localhost-cert.pem" "$TLS_CERT"
  /usr/bin/ditto "$tmp_dir/localhost-key.pem" "$TLS_KEY"

  chmod 644 "$TLS_CA" "$TLS_CERT"
  chmod 600 "$TLS_KEY"

  echo "MailNotes-CA im System-Schlüsselbund als vertrauenswürdig eintragen ..."
  echo "macOS fragt hierfür ggf. nach dem Administrator-Kennwort."
  sudo /usr/bin/security add-trusted-cert \
    -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    "$TLS_CA"

  if ! /usr/bin/security verify-cert -c "$TLS_CERT" -p ssl -s localhost >/dev/null 2>&1; then
    echo "Fehler: Das neue MailNotes-TLS-Zertifikat wird von macOS nicht als vertrauenswürdig akzeptiert."
    exit 5
  fi

  rm -rf "$tmp_dir"
  trap - RETURN
}

echo "MailNotesAgent für macOS installieren"
echo

STAGING_APP="$INSTALL_APP.staging"
ROLLBACK_APP="$INSTALL_APP.rollback"
if [ -e "$STAGING_APP" ] || [ -e "$ROLLBACK_APP" ]; then
  echo "Fehler: Staging/Rollback einer vorigen Installation vorhanden."
  echo "Bitte diese Installation zuerst pruefen:"
  echo "  $INSTALL_APP"
  exit 6
fi

WAS_LOADED=0
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  WAS_LOADED=1
elif /usr/sbin/lsof -nP -iTCP:48571 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Fehler: Port 48571 wird bereits verwendet."
  echo "Bitte den manuell gestarteten MailNotes-Agenten zuerst beenden."
  exit 6
fi

echo "Installationsverzeichnisse anlegen ..."
mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR" "$HOME/Library/Logs" "$TLS_DIR"

if tls_is_ready; then
  echo "Vorhandenes MailNotes-TLS-Zertifikat ist gültig und vertrauenswürdig."
else
  echo "MailNotes-TLS-Zertifikat fehlt, ist ungültig oder nicht vertrauenswürdig."
  create_tls_material
fi

# Vor dem Stoppen der laufenden Installation die vollstaendige Kopie pruefen.
echo "App-Bundle vorbereiten ..."
/usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
if ! /usr/bin/codesign --verify --deep --strict "$STAGING_APP"; then
  rm -rf "$STAGING_APP"
  exit 6
fi

STATE_DIR="$(mktemp -d)"
HAD_PLIST=0
if [ -f "$PLIST_TARGET" ]; then
  cp "$PLIST_TARGET" "$STATE_DIR/previous.plist"
  HAD_PLIST=1
fi
OLD_MOVED=0
NEW_INSTALLED=0
LAUNCH_CHANGED=0

rollback_installation() {
  local result=$?
  trap - EXIT
  if [ "$result" -ne 0 ]; then
    echo "Installation fehlgeschlagen. Vorigen Stand wiederherstellen ..."
    if [ "$LAUNCH_CHANGED" -eq 1 ]; then
      launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
    fi
    if [ "$NEW_INSTALLED" -eq 1 ]; then
      rm -rf "$INSTALL_APP"
    fi
    if [ "$OLD_MOVED" -eq 1 ]; then
      mv "$ROLLBACK_APP" "$INSTALL_APP" || {
        echo "Fehler: Manuelle Wiederherstellung aus $ROLLBACK_APP erforderlich."
        exit "$result"
      }
    fi
    if [ "$LAUNCH_CHANGED" -eq 1 ]; then
      if [ "$HAD_PLIST" -eq 1 ]; then
        cp "$STATE_DIR/previous.plist" "$PLIST_TARGET"
      else
        rm -f "$PLIST_TARGET"
      fi
      if [ "$WAS_LOADED" -eq 1 ]; then
        launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET" || true
      fi
    fi
    rm -rf "$STAGING_APP"
  fi
  rm -rf "$STATE_DIR"
  exit "$result"
}
trap rollback_installation EXIT

if [ "$WAS_LOADED" -eq 1 ]; then
  echo "Vorhandenen LaunchAgent stoppen ..."
  LAUNCH_CHANGED=1
  launchctl bootout "gui/$(id -u)" "$PLIST_TARGET"
fi

echo "MailNotesAgent.app installieren ..."
if [ -d "$INSTALL_APP" ]; then
  mv "$INSTALL_APP" "$ROLLBACK_APP"
  OLD_MOVED=1
fi
mv "$STAGING_APP" "$INSTALL_APP"
NEW_INSTALLED=1

echo "LaunchAgent-Konfiguration erzeugen ..."
# HOME sowohl fuer XML als auch fuer die sed-Ersetzung maskieren.
XML_HOME=$(printf '%s' "$HOME" | sed 's/\&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
ESCAPED_HOME=$(printf '%s' "$XML_HOME" | sed 's/[&|\\]/\\&/g')
LAUNCH_CHANGED=1
sed "s|@@HOME@@|$ESCAPED_HOME|g" "$PLIST_TEMPLATE" > "$PLIST_TARGET"
plutil -lint "$PLIST_TARGET"

echo "LaunchAgent laden ..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"

echo "Start und HTTPS-Verbindung pruefen ..."
READY=0
for attempt in $(seq 1 15); do
  if curl --silent --show-error --fail --max-time 2 https://localhost:48571/version > "$STATE_DIR/version.json" 2>/dev/null; then
    RUNNING_VERSION=$(plutil -extract version raw -o - "$STATE_DIR/version.json" 2>/dev/null || true)
    RUNNING_PATH=$(plutil -extract agentPath raw -o - "$STATE_DIR/version.json" 2>/dev/null || true)
    if [ "$RUNNING_VERSION" = "$EXPECTED_VERSION" ] &&
       [ "$RUNNING_PATH" = "$INSTALL_APP/Contents/MacOS/MailNotesAgent" ]; then
      READY=1
      break
    fi
  fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "Fehler: Der installierte Agent antwortet nicht mit der erwarteten Version."
  echo "Fehlerprotokoll: $HOME/Library/Logs/MailNotesAgent-error.log"
  exit 5
fi

if [ "$OLD_MOVED" -eq 1 ]; then
  rm -rf "$ROLLBACK_APP"
fi
echo
echo "MailNotesAgent $EXPECTED_VERSION wurde erfolgreich installiert und gestartet."
