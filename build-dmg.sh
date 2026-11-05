#!/bin/bash
# Builds the Kartov Cleaner DMG: compiles, signs, lays out an installer window
# (background, icon positions, Applications shortcut) and notarizes it when a notary profile exists.
set -u
cd "$(dirname "$0")"
pause() { [ -n "${KARTOV_NO_PAUSE:-}" ] && return; echo ""; echo "Press any key to close…"; read -n 1; }
fail() { echo ""; echo "✗ $1"; [ -n "${2:-}" ] && tail -15 "$2"; pause; exit 1; }

VERSION="$(tr -d ' \n' < VERSION 2>/dev/null)"
VERSION="${VERSION:-0.0}"
NAME="Kartov Cleaner"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"

echo ""
echo "▸ Making the DMG for $NAME $VERSION"
# A release must carry a real signature, otherwise every update makes macOS forget the app's permissions.
source ./Packaging/signing.sh
ensure_local_identity || fail "No signing certificate. Without it every update resets Full Disk Access, so no DMG was made."
KARTOV_APP_DIR="$STAGE" KARTOV_NO_OPEN=1 bash ./install.sh || fail "Build or signing failed (see the lines above)."
source ./Packaging/signing.sh
is_certificate_signed "$STAGE/$NAME.app" || fail "The app came out ad-hoc signed; no DMG was made (it would reset permissions on update)."
echo "  ✓ Signed with: $(signing_label)"

# Contents of the installer window
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
tiffutil -cathidpicheck Packaging/background.png Packaging/background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 \
  || cp Packaging/background.png "$STAGE/.background/background.png"
BG="$(ls "$STAGE/.background" | head -1)"
cp AppIcon.icns "$STAGE/.VolumeIcon.icns"

echo "▸ Laying out the installer window…"
RW="$WORK/rw.dmg"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/tmp/kartov-dmg.log 2>&1 \
  || fail "Could not create the disk image." /tmp/kartov-dmg.log
VOL="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" 2>>/tmp/kartov-dmg.log | grep -o '/Volumes/.*$' | head -1)"
[ -d "$VOL" ] || fail "Could not mount the disk image." /tmp/kartov-dmg.log
DISK="$(basename "$VOL")"
SetFile -a C "$VOL" >/dev/null 2>&1 || true   # volume icon

# Finder window: 660×420, no toolbar, the two icons sit in the boxes drawn on the background.
# The first time, macOS asks whether Terminal may control Finder: allow it.
osascript >/tmp/kartov-finder.log 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 568}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:$BG"
    set position of item "$NAME.app" of container window to {170, 214}
    set position of item "Applications" of container window to {490, 214}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
[ $? -eq 0 ] || echo "  (Window layout could not be applied; the DMG still works. Details: /tmp/kartov-finder.log)"
sync
hdiutil detach "$VOL" -quiet || hdiutil detach "$VOL" -force -quiet

mkdir -p "dist"
OUT="dist/$NAME $VERSION.dmg"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >>/tmp/kartov-dmg.log 2>&1 \
  || fail "Could not compress the DMG." /tmp/kartov-dmg.log
rm -rf "$WORK"

if [ -n "$IDENTITY" ]; then
  echo "▸ Signing the DMG…"
  codesign --force --timestamp --sign "$IDENTITY" "$OUT" || fail "Could not sign the DMG."
  if has_notary_profile; then
    echo "▸ Sending to Apple for notarization (this can take a few minutes)…"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait >/tmp/kartov-notary.log 2>&1
    if grep -q "status: Accepted" /tmp/kartov-notary.log; then
      xcrun stapler staple "$OUT" >/dev/null 2>&1 && echo "✓ Notarized; it opens on any Mac without warnings."
    else
      echo "✗ Notarization was rejected. For details:"
      grep -E "id:|status:" /tmp/kartov-notary.log | head -4
      echo "  xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
    fi
  else
    echo "! No notary profile ($NOTARY_PROFILE): the DMG is signed but not notarized."
  fi
else
  echo "! No Developer ID certificate: the DMG is ad-hoc signed. Other Macs will show a \"cannot be verified\" warning."
  fi

shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"   # the in-app updater checks this

echo ""
echo "✓ Ready: $(pwd)/$OUT"
[ -z "${KARTOV_NO_PAUSE:-}" ] && open -R "$OUT"
[ -z "${KARTOV_NO_PAUSE:-}" ] && pause
exit 0
