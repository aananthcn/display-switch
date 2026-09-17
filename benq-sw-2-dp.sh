#!/bin/bash
# Switch the BenQ GW2790QT to DisplayPort-1 input (the Linux PC).
# Bound to Ctrl+Alt+Home as a GNOME custom keyboard shortcut.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUS="$("$SCRIPT_DIR/detect-benq-bus.sh")" || exit 1
timeout 15 /usr/bin/ddcutil setvcp 60 0x0f --bus "$BUS"
