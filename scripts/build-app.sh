#!/bin/bash
# Assemble hyprmac.app from the SwiftPM build. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/hyprmac.app"

cd "$ROOT"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/hyprmac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/hyprmac"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>hyprmac</string>
    <key>CFBundleIdentifier</key>
    <string>dev.hyprmac.hyprmac</string>
    <key>CFBundleName</key>
    <string>hyprmac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Prefer the stable self-signed identity so the Accessibility grant survives
# rebuilds; fall back to ad-hoc. Distribution needs a Developer ID
# certificate + notarization; see README.
IDENTITY="hyprmac-dev"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    IDENTITY="-"
    echo "note: hyprmac-dev cert not found, ad-hoc signing (permission re-grant needed per rebuild)"
fi
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"
