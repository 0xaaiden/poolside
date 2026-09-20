#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="../Luma LP.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
LUMA_SDK="${LUMA_SDK:-$(xcrun --show-sdk-path)}"
swiftc -sdk "$LUMA_SDK" -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 Sources/LumaLP/Models.swift Sources/LumaLP/App.swift Sources/LumaLP/Views.swift -o "$APP/Contents/MacOS/LumaLP"
cp Sources/LumaLP/Resources/sample.json "$APP/Contents/Resources/sample.json"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LumaLP</string>
<key>CFBundleIdentifier</key><string>local.luma.lp.prototype</string>
<key>CFBundleName</key><string>Luma LP</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
