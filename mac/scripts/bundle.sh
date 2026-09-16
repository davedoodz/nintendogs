#!/usr/bin/env bash
# Build Nintendogs.app (SwiftPM, no Xcode project). Usage: mac/scripts/bundle.sh [debug|release]
set -euo pipefail
CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}

APP_NAME=Nintendogs
BUNDLE_ID=studio.david.nintendogs
if [[ ! -f "$ROOT/Assets/shiba/aSib_a.nsbmd/Sib_a.dae" ]]; then
  echo "Missing Shiba assets. From the repository root, run npm run assets:mac." >&2
  exit 1
fi
swift build -c "$CONF"

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
cp ".build/$CONF/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
# Local game rips travel inside the bundle; they are git-ignored at mac/Assets.
cp -R "$ROOT/Assets" "$APP/Contents/Resources/Assets"
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Created $APP"
