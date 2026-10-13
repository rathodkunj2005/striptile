#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product StripTile
BIN=$(swift build -c release --show-bin-path)/StripTile
APP=build/StripTile.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/StripTile"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.rathodkunj2005.striptile</string>
<key>CFBundleName</key><string>StripTile</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>StripTile</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
if [ -z "${STRIPTILE_SIGN_IDENTITY+x}" ]; then
    if security find-identity -p codesigning | grep -q "StripTile Local Signing"; then
        STRIPTILE_SIGN_IDENTITY="StripTile Local Signing"
    else
        STRIPTILE_SIGN_IDENTITY="-"
    fi
fi
codesign --force --sign "$STRIPTILE_SIGN_IDENTITY" "$APP"
echo "signed with: $STRIPTILE_SIGN_IDENTITY"
echo "built $APP"
