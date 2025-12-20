#!/bin/bash
set -e

APP_NAME="FixedCursor"
APP_BUNDLE="$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_BUNDLE"

# Parse flags
BUILD_CONFIG="release"
if [[ "$1" == "--debug" ]]; then
    BUILD_CONFIG="debug"
fi

# Kill running instance if any
pkill -x "$APP_NAME" 2>/dev/null || true

# Build
echo "Building ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG"

# Remove existing app from Applications
rm -rf "$INSTALL_PATH"

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp ".build/$BUILD_CONFIG/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FixedCursor</string>
    <key>CFBundleIdentifier</key>
    <string>com.fixedcursor.app</string>
    <key>CFBundleName</key>
    <string>FixedCursor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Move to Applications
mv "$APP_BUNDLE" "$INSTALL_PATH"

# Code sign to preserve accessibility permissions across rebuilds
codesign --force --sign "FixedCursor Dev" "$INSTALL_PATH"

echo "Installed to $INSTALL_PATH"

# Launch the app
open "$INSTALL_PATH"
