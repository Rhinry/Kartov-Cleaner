# Ortak: Developer ID imza kimliğini ve noter profilini bulur. kur.sh ve dmg.sh "source" eder.
NOTARY_PROFILE="kartov-notary"
ENTITLEMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Kartov.entitlements"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"

# İmzalar: Developer ID varsa onunla (hardened runtime + zaman damgası), yoksa yerel ad-hoc imza.
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
