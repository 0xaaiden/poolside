#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="../Poolside.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
source ./sdk.sh
POOLSIDE_SDK="$(poolside_sdk)"
swiftc -sdk "$POOLSIDE_SDK" -parse-as-library -swift-version 6 -target arm64-apple-macosx14.0 Sources/Poolside/Models.swift Sources/Poolside/License.swift Sources/Poolside/Icons.swift Sources/Poolside/App.swift Sources/Poolside/Views.swift -o "$APP/Contents/MacOS/Poolside"
cp Sources/Poolside/Resources/sample.json Sources/Poolside/Resources/sample-closed.json "$APP/Contents/Resources/"
cp -R Sources/Poolside/Resources/Icons "$APP/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
# Keep the bundle identifier stable so existing wallet and appearance preferences survive the rename.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Poolside</string>
<key>CFBundleIdentifier</key><string>local.luma.lp.prototype</string>
<key>CFBundleName</key><string>Poolside</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
