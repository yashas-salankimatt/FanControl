#!/bin/bash
set -e

HELPER_NAME="FanControlHelper"
HELPER_DEST="/Library/PrivilegedHelperTools/$HELPER_NAME"
PLIST_NAME="com.fancontrol.helper"
PLIST_DEST="/Library/LaunchDaemons/$PLIST_NAME.plist"
SOCKET_PATH="/var/run/fancontrol.sock"

echo "=== FanControl Helper Uninstaller ==="
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges."
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# Stop and unload daemon
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "Stopping helper daemon..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Remove files
echo "Removing helper binary..."
rm -f "$HELPER_DEST"

echo "Removing LaunchDaemon plist..."
rm -f "$PLIST_DEST"

echo "Removing socket..."
rm -f "$SOCKET_PATH"

echo "Removing log..."
rm -f /var/log/fancontrol-helper.log

echo ""
echo "=== Helper uninstalled. ==="
echo "  Fan speeds have been restored to automatic mode."
