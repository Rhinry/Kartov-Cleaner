#!/bin/bash
# Kartov Cleaner kurulumu: derler, "Kartov Cleaner.app" yapar, Uygulamalar'a koyar ve açar.
set -u
cd "$(dirname "$0")"

# KARTOV_APP_DIR: where to put the .app (DMG Oluştur.command uses a temporary folder).
APP_DIR="${KARTOV_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Kartov Cleaner.app"

echo ""
echo "▸ Kartov Cleaner derleniyor (ilk sefer 1-3 dakika sürebilir)…"
CLT="/Library/Developer/CommandLineTools"

build() {
  swift build -c release > /tmp/kartov-build.log 2>&1
  grep -E "Compiling|Build complete" /tmp/kartov-build.log | tail -3
}

build
# Xcode yüklü ama lisansı kabul edilmemişse: Komut Satırı Araçları ile derle.
if grep -qi "license" /tmp/kartov-build.log && [ -d "$CLT" ]; then
  echo "  Xcode lisansı kabul edilmemiş; Komut Satırı Araçları ile devam ediliyor…"
  export DEVELOPER_DIR="$CLT"
  build
fi

if grep -q "error:" /tmp/kartov-build.log || grep -qi "license" /tmp/kartov-build.log; then
  echo ""
  echo "✗ Derleme olmadı. Hata ayrıntıları:"
  echo "--------------------------------------------------------------"
  grep -Ei "error:|license" /tmp/kartov-build.log | sort -u | head -30
  exit 1
fi

BIN="$(swift build -c release --show-bin-path 2>/dev/null)"
EXE="$BIN/KartovCleaner"
RES="$(find "$BIN" -maxdepth 1 -name "*KartovCore*.bundle" 2>/dev/null | head -1)"
if [ -z "$BIN" ] || [ ! -x "$EXE" ] || [ -z "$RES" ]; then
  echo "✗ Derlenen dosyalar bulunamadı (\"$BIN\"). Derleme kaydı:"
  tail -20 /tmp/kartov-build.log
  exit 1
fi

echo "▸ Uygulama paketi hazırlanıyor…"
if [ -z "${KARTOV_NO_OPEN:-}" ]; then
  osascript -e 'tell application "Kartov Cleaner" to quit' >/dev/null 2>&1 || true
  pkill -x KartovCleaner >/dev/null 2>&1 || true
fi
mkdir -p "$APP_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/KartovCleaner"
cp -R "$RES" "$APP/Contents/Resources/"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION="$(tr -d ' \n' < VERSION 2>/dev/null)"; VERSION="${VERSION:-0.0}"
BUILD_NUMBER="$(echo "$VERSION" | tr -d '.')"
REPO="$(tr -d ' \n' < Paketleme/github-repo.txt 2>/dev/null)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kartov Cleaner</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string><string>de</string><string>es</string></array>
  <key>CFBundleDisplayName</key><string>Kartov Cleaner</string>
  <key>CFBundleIdentifier</key><string>com.kartov.cleaner</string>
  <key>CFBundleExecutable</key><string>KartovCleaner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>KartovUpdateRepo</key><string>$REPO</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Sistem Verisi temizliğinde macOS'un yönetici şifresi penceresini açmak için.</string>
</dict>
</plist>
PLIST

source ./Paketleme/imza.sh
if [ -n "$IDENTITY" ]; then echo "▸ İmzalanıyor: $IDENTITY"; else echo "▸ Yerel imza (Developer ID sertifikası yok)"; fi
sign_app "$APP" >/tmp/kartov-sign.log 2>&1 || { echo "✗ İmzalama olmadı:"; tail -8 /tmp/kartov-sign.log; exit 1; }
touch "$APP"   # Finder ve Dock yeni logoyu görsün

if [ -n "${KARTOV_NO_OPEN:-}" ]; then
  echo "✓ Uygulama paketi hazır: $APP"
  exit 0
fi

echo ""
echo "✓ Kuruldu: $APP"
echo "  Bundan sonra Spotlight'ta (⌘ Boşluk) \"Kartov\" yazıp açabilirsin."
echo "  Tam Disk Erişimi için: Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi › + › Ev klasörü › Uygulamalar › Kartov Cleaner"
echo ""
open "$APP"
