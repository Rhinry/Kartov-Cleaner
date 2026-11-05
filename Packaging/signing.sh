# Shared by install.sh and build-dmg.sh: finds a Developer ID signing identity and the notary profile.
NOTARY_PROFILE="kartov-notary"
ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Kartov.entitlements"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"

# Signs with the Developer ID if there is one (hardened runtime + timestamp), otherwise ad-hoc.
sign_app() {
  local app="$1"
  if [ -n "$IDENTITY" ]; then
    codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$app" \
      && codesign --verify --strict --deep "$app"
  else
    codesign --force --deep --sign - "$app"
  fi
}

has_notary_profile() {
  [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}
