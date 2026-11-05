# Shared by install.sh and build-dmg.sh: finds (or creates) the signing identity and the notary profile.
# Order: Developer ID (Apple) > a persistent local certificate "Kartov Cleaner Local Signing" > ad-hoc.
NOTARY_PROFILE="kartov-notary"
LOCAL_IDENTITY_NAME="Kartov Cleaner Local Signing"
ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Kartov.entitlements"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SIGNING_BACKUP_DIR="${KARTOV_SIGNING_BACKUP:-$HOME/Documents/Kartov Cleaner Signing Backup}"

find_identities() {
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
  LOCAL_IDENTITY=""
  if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY_NAME"; then
    LOCAL_IDENTITY="$LOCAL_IDENTITY_NAME"
  fi
}
find_identities

# Creates the persistent local certificate once (10 years) and backs it up.
# Every build signed with it is "the same app" to macOS, so Full Disk Access survives updates.
ensure_local_identity() {
  [ -n "$IDENTITY" ] || [ -n "$LOCAL_IDENTITY" ] && return 0
  echo "▸ Creating the persistent signing certificate (one time only)…"
  local tmp; tmp="$(mktemp -d)"
  cat > "$tmp/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $LOCAL_IDENTITY_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
  local pass; pass="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cfg" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$LOCAL_IDENTITY_NAME" \
         -out "$tmp/signing.p12" -passout "pass:$pass" >/dev/null 2>&1 \
    && security import "$tmp/signing.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null \
    || { echo "✗ Could not create the signing certificate."; rm -rf "$tmp"; return 1; }
  echo "  macOS will ask for your Mac password to trust the certificate for code signing."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" >/dev/null 2>&1 \
    || echo "  (Trust step skipped; signing still works.)"
  mkdir -p "$SIGNING_BACKUP_DIR"
  cp "$tmp/signing.p12" "$SIGNING_BACKUP_DIR/$LOCAL_IDENTITY_NAME.p12"
  printf 'Password: %s\n\nKeep this folder safe and NEVER upload it to GitHub.\nIf this certificate is lost, future versions are signed differently: users must grant\nFull Disk Access again and the in-app updater refuses the new version.\nTo use it on another Mac: double-click the .p12 file and enter this password.\n' "$pass" \
    > "$SIGNING_BACKUP_DIR/README - password.txt"
  rm -rf "$tmp"
  echo "  ✓ Certificate ready. Backup: $SIGNING_BACKUP_DIR"
  find_identities
  [ -n "$LOCAL_IDENTITY" ]
}

# Developer ID: hardened runtime + timestamp. Local certificate: same signature on every build. Else ad-hoc.
sign_app() {
  local app="$1"
  if [ -n "$IDENTITY" ]; then
    codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$app" \
      && codesign --verify --strict --deep "$app"
  elif [ -n "$LOCAL_IDENTITY" ]; then
    codesign --force --deep --sign "$LOCAL_IDENTITY" "$app" && codesign --verify --deep "$app"
  else
    codesign --force --deep --sign - "$app"
  fi
}

# True when the app carries a real certificate signature (not ad-hoc).
is_certificate_signed() {
  codesign -d -r- "$1" 2>&1 | grep -Eq 'certificate leaf|anchor apple generic'
}

signing_label() {
  if [ -n "$IDENTITY" ]; then echo "$IDENTITY"
  elif [ -n "$LOCAL_IDENTITY" ]; then echo "$LOCAL_IDENTITY (persistent local certificate)"
  else echo "ad-hoc (macOS asks for permissions again after every update)"; fi
}

has_notary_profile() {
  [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}
