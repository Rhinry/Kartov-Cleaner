# Shared by install.sh and build-dmg.sh: finds the signing identity and the notary profile.
# Order: Developer ID (Apple) > a persistent local certificate named "Kartov Cleaner Local Signing" > ad-hoc.
NOTARY_PROFILE="kartov-notary"
LOCAL_IDENTITY_NAME="Kartov Cleaner Local Signing"
ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Kartov.entitlements"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
LOCAL_IDENTITY=""
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY_NAME"; then
  LOCAL_IDENTITY="$LOCAL_IDENTITY_NAME"
fi

# Developer ID: hardened runtime + timestamp. Persistent local certificate: the same signature on every
# build, so macOS keeps permissions (Full Disk Access) across updates. Otherwise ad-hoc.
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

signing_label() {
  if [ -n "$IDENTITY" ]; then echo "$IDENTITY"
  elif [ -n "$LOCAL_IDENTITY" ]; then echo "$LOCAL_IDENTITY (persistent local certificate)"
  else echo "ad-hoc (macOS asks for permissions again after every update)"; fi
}

has_notary_profile() {
  [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}
