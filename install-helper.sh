#!/bin/bash
set -e

cd "$(dirname "$0")"

HELPER_NAME="FanControlHelper"
HELPER_DEST="/Library/PrivilegedHelperTools/$HELPER_NAME"
PLIST_NAME="com.fancontrol.helper"
PLIST_DEST="/Library/LaunchDaemons/$PLIST_NAME.plist"

echo "=== FanControl Helper Installer ==="
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges."
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# Build the helper
echo "Building helper daemon..."
swift build -c release --product "$HELPER_NAME" 2>&1

# Stop existing daemon if running
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "Stopping existing helper daemon..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Install helper binary
echo "Installing helper to $HELPER_DEST..."
mkdir -p /Library/PrivilegedHelperTools
cp ".build/release/$HELPER_NAME" "$HELPER_DEST"
chown root:wheel "$HELPER_DEST"
chmod 755 "$HELPER_DEST"

# Install LaunchDaemon plist
echo "Installing LaunchDaemon plist..."
cp "Resources/$PLIST_NAME.plist" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

# Load the daemon
echo "Loading helper daemon..."
launchctl load "$PLIST_DEST"

# Verify
sleep 1
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo ""
    echo "=== Helper installed and running! ==="
    echo "  The FanControl app can now control fan speeds."
    echo "  The helper will start automatically on boot."
    echo ""
    echo "  To uninstall: sudo ./uninstall-helper.sh"
else
    echo ""
    echo "WARNING: Helper may not have started. Check /var/log/fancontrol-helper.log"
fi
