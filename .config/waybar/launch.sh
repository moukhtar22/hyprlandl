#!/usr/bin/env bash
# Waybar has been completely migrated to Quickshell (BarraWaybar.qml)
# Terminate any stray Waybar processes so only Quickshell runs.
pkill -x waybar 2>/dev/null || true
pkill -x .waybar-wrapped 2>/dev/null || true

# Ensure Quickshell Island & Bar service is running
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active waybar-island.service >/dev/null 2>&1; then
    exit 0
elif [ -x "$HOME/.local/bin/quickshell-island" ]; then
    "$HOME/.local/bin/quickshell-island" &
fi
exit 0
