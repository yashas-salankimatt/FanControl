#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building FanControl app..."
swift build -c release --product FanControlApp 2>&1

echo ""
echo "Building helper daemon..."
swift build -c release --product FanControlHelper 2>&1

echo ""
echo "Building CLI tool..."
swift build -c release --product FanControlCLI 2>&1
echo "CLI built at .build/release/FanControlCLI"

# Assemble .app bundle
APP_DIR="FanControl.app/Contents"
rm -rf FanControl.app
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/FanControlApp "$APP_DIR/MacOS/"
cp Resources/Info.plist "$APP_DIR/"

# Bundle helper binary and plist inside .app for in-app installation
echo "Bundling helper daemon into app..."
cp .build/release/FanControlHelper "$APP_DIR/Resources/"
cp Resources/com.fancontrol.helper.plist "$APP_DIR/Resources/"

echo "Code signing..."
codesign --force --deep --sign - FanControl.app

echo ""
echo "=== Build complete! ==="
echo "  FanControl.app is ready."
echo "  The helper daemon is bundled inside the app."
echo "  The app will prompt to install the helper on first launch."
echo ""
echo "To run:"
echo "  open FanControl.app"
