#!/bin/bash
# Kartov Cleaner DMG'si: derler, imzalar, tasarımlı bir kurulum penceresi hazırlar
# (arka plan, ikon yerleri, Applications kısayolu), varsa Apple noter onayı alır.
set -u
cd "$(dirname "$0")"
pause() { [ -n "${KARTOV_NO_PAUSE:-}" ] && return; echo ""; echo "Kapatmak için bir tuşa bas…"; read -n 1; }
fail() { echo ""; echo "✗ $1"; [ -n "${2:-}" ] && tail -15 "$2"; pause; exit 1; }

VERSION="$(tr -d ' \n' < VERSION 2>/dev/null)"
VERSION="${VERSION:-0.0}"
NAME="Kartov Cleaner"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"

echo ""
echo "▸ $NAME $VERSION için DMG hazırlanıyor"
KARTOV_APP_DIR="$STAGE" KARTOV_NO_OPEN=1 bash ./kur.sh || fail "Derleme ya da imza olmadı (yukarıdaki satırlara bak)."
source ./Paketleme/imza.sh

# Kurulum penceresinin içeriği
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
tiffutil -cathidpicheck Paketleme/arkaplan.png Paketleme/arkaplan@2x.png -out "$STAGE/.background/arkaplan.tiff" >/dev/null 2>&1 \
  || cp Paketleme/arkaplan.png "$STAGE/.background/arkaplan.png"
BG="$(ls "$STAGE/.background" | head -1)"
cp AppIcon.icns "$STAGE/.VolumeIcon.icns"

echo "▸ Kurulum penceresi tasarlanıyor…"
RW="$WORK/rw.dmg"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/tmp/kartov-dmg.log 2>&1 \
  || fail "Disk görüntüsü oluşturulamadı." /tmp/kartov-dmg.log
VOL="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" 2>>/tmp/kartov-dmg.log | grep -o '/Volumes/.*$' | head -1)"
[ -d "$VOL" ] || fail "Disk görüntüsü bağlanamadı." /tmp/kartov-dmg.log
DISK="$(basename "$VOL")"
SetFile -a C "$VOL" >/dev/null 2>&1 || true   # birim ikonu

# Finder penceresi: 660×420, araç çubuğu yok, iki ikon arka plandaki kutulara oturur.
# İlk seferde macOS "Terminal, Finder'ı denetlemek istiyor" diye sorar: İzin Ver.
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
[ $? -eq 0 ] || echo "  (Pencere düzeni uygulanamadı; DMG yine de çalışır. Ayrıntı: /tmp/kartov-finder.log)"
sync
hdiutil detach "$VOL" -quiet || hdiutil detach "$VOL" -force -quiet

mkdir -p "Dağıtım"
OUT="Dağıtım/$NAME $VERSION.dmg"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >>/tmp/kartov-dmg.log 2>&1 \
  || fail "DMG sıkıştırılamadı." /tmp/kartov-dmg.log
rm -rf "$WORK"

if [ -n "$IDENTITY" ]; then
  echo "▸ DMG imzalanıyor…"
  codesign --force --timestamp --sign "$IDENTITY" "$OUT" || fail "DMG imzalanamadı."
  if has_notary_profile; then
    echo "▸ Apple noter onayına gönderiliyor (birkaç dakika sürebilir)…"
    xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait >/tmp/kartov-notary.log 2>&1
    if grep -q "status: Accepted" /tmp/kartov-notary.log; then
      xcrun stapler staple "$OUT" >/dev/null 2>&1 && echo "✓ Noter onayı alındı; her Mac'te uyarısız açılır."
    else
      echo "✗ Noter onayı reddedildi. Ayrıntı için:"
      grep -E "id:|status:" /tmp/kartov-notary.log | head -4
      echo "  xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
    fi
  else
    echo "! Noter profili yok: DMG imzalı ama noter onaysız."
  fi
else
  echo "! Developer ID sertifikası yok: DMG yerel imzalı. Başka Mac'lerde 'doğrulanamadı' uyarısı çıkar."
fi

shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"   # güncelleyici bununla doğrular

echo ""
echo "✓ Hazır: $(pwd)/$OUT"
[ -z "${KARTOV_NO_PAUSE:-}" ] && open -R "$OUT"
[ -z "${KARTOV_NO_PAUSE:-}" ] && pause
exit 0
