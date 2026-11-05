#!/bin/bash
# Builds Kartov Cleaner, makes "Kartov Cleaner.app", puts it in ~/Applications and opens it.
set -u
cd "$(dirname "$0")"

# KARTOV_APP_DIR: where to put the .app (build-dmg.sh uses a temporary folder).
APP_DIR="${KARTOV_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Kartov Cleaner.app"

echo ""
echo "▸ Building Kartov Cleaner (the first build can take 1–3 minutes)…"
CLT="/Library/Developer/CommandLineTools"

build() {
  swift build -c release > /tmp/kartov-build.log 2>&1
  grep -E "Compiling|Build complete" /tmp/kartov-build.log | tail -3
}

build
# Xcode installed but its license not accepted: fall back to the Command Line Tools.
if grep -qi "license" /tmp/kartov-build.log && [ -d "$CLT" ]; then
  echo "  Xcode license not accepted; continuing with the Command Line Tools…"
  export DEVELOPER_DIR="$CLT"
  build
fi

if grep -q "error:" /tmp/kartov-build.log || grep -qi "license" /tmp/kartov-build.log; then
  echo ""
  echo "✗ Build failed:"
  echo "--------------------------------------------------------------"
  grep -Ei "error:|license" /tmp/kartov-build.log | sort -u | head -30
  exit 1
fi

BIN="$(swift build -c release --show-bin-path 2>/dev/null)"
EXE="$BIN/KartovCleaner"
RES="$(find "$BIN" -maxdepth 1 -name "*KartovCore*.bundle" 2>/dev/null | head -1)"
if [ -z "$BIN" ] || [ ! -x "$EXE" ] || [ -z "$RES" ]; then
  echo "✗ Build output not found (\"$BIN\"). Build log:"
  tail -20 /tmp/kartov-build.log
  exit 1
fi

echo "▸ Making the app bundle…"
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
REPO="$(tr -d ' \n' < Packaging/github-repo.txt 2>/dev/null)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Kartov Cleaner</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>tr</string><string>de</string><string>es</string></array>
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
  <key>NSAppleEventsUsageDescription</key><string>Opens the macOS administrator password prompt when freeing memory or cleaning System Data.</string>
</dict>
</plist>
PLIST

source ./Packaging/signing.sh
echo "▸ Signing: $(signing_label)"
sign_app "$APP" >/tmp/kartov-sign.log 2>&1 || { echo "✗ Signing failed:"; tail -8 /tmp/kartov-sign.log; exit 1; }
touch "$APP"   # so Finder and the Dock pick up the icon

if [ -n "${KARTOV_NO_OPEN:-}" ]; then
  echo "✓ App bundle ready: $APP"
  exit 0
fi

echo ""
echo "✓ Installed: $APP"
echo "  Open it any time from Spotlight (⌘ Space) by typing \"Kartov\"."
echo "  Full Disk Access: System Settings › Privacy & Security › Full Disk Access › + › Home › Applications › Kartov Cleaner"
echo ""
open "$APP"
