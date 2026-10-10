#!/bin/bash
# Builds the release JA11EQ executable and assembles an ad-hoc signed "dist/JA11 EQ.app".
set -euo pipefail

fail() { echo "make-app.sh: step '$1' failed: $2" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Building release JA11EQ"
swift build -c release --product JA11EQ || fail build "swift build returned an error"
BIN_DIR="$(swift build -c release --show-bin-path)" || fail locate "could not resolve bin path"
BIN="$BIN_DIR/JA11EQ"
[ -f "$BIN" ] || fail locate "binary missing at $BIN"

APP="$ROOT/dist/JA11 EQ.app"
case "$APP" in
  */dist/"JA11 EQ.app") ;;
  *) fail clean "refusing to remove unexpected path: $APP" ;;
esac
[ -n "$APP" ] || fail clean "empty app path"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" || fail layout "mkdir"
cp "$BIN" "$APP/Contents/MacOS/JA11 EQ" || fail copy "copy binary"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>JA11 EQ</string>
    <key>CFBundleDisplayName</key>
    <string>JA11 EQ</string>
    <key>CFBundleExecutable</key>
    <string>JA11 EQ</string>
    <key>CFBundleIdentifier</key>
    <string>local.ja11.eq</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail plist "plutil -lint"

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP" || fail sign "codesign"
codesign --verify --deep --strict "$APP" || fail verify "codesign --verify"

echo "Built: dist/JA11 EQ.app"
echo "Open it with: open \"dist/JA11 EQ.app\""
