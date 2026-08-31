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

# Bereits geladenen LaunchAgent sauber entladen.
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "Vorhandenen LaunchAgent stoppen ..."
  launchctl bootout "gui/$(id -u)" "$PLIST_TARGET" >/dev/null 2>&1 || true
fi

echo "Installationsverzeichnisse anlegen ..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCH_AGENTS_DIR"
mkdir -p "$HOME/Library/Logs"
mkdir -p "$TLS_DIR"

if tls_is_ready; then
  echo "Vorhandenes MailNotes-TLS-Zertifikat ist gültig und vertrauenswürdig."
else
  echo "MailNotes-TLS-Zertifikat fehlt, ist ungültig oder nicht vertrauenswürdig."
  create_tls_material
fi

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
if curl --silent --fail --max-time 3 https://localhost:48571/ping; then
  echo
  echo "MailNotesAgent wurde erfolgreich installiert und gestartet."
else
  echo
  echo "WARNUNG: MailNotesAgent antwortet noch nicht per HTTPS auf Port 48571."
  echo "Fehlerprotokoll:"
  echo "  $HOME/Library/Logs/MailNotesAgent-error.log"
  exit 5
fi
