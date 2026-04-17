#!/bin/bash
# Monitor Switcher - macOS Launcher
# This script launches the monitor switcher from any directory
# Default: switch to windows if no parameter is provided

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/macos/monitor_switcher.sh" ]; then
    echo "Error: monitor_switcher.sh not found in macos directory"
    echo "Please check the installation."
    exit 1
fi

# Make sure the script is executable
chmod +x "$SCRIPT_DIR/macos/monitor_switcher.sh"

# Set default parameter to "windows" if no parameter is provided
if [ -z "$1" ]; then
    "$SCRIPT_DIR/macos/monitor_switcher.sh" switch windows
else
    "$SCRIPT_DIR/macos/monitor_switcher.sh" "$@"
fi
