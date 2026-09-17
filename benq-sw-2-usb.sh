#!/bin/bash
# Switch the BenQ GW2790QT to USB-C input (the Windows PC).
# Bound to Ctrl+Alt+End as a GNOME custom keyboard shortcut.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUS="$("$SCRIPT_DIR/detect-benq-bus.sh")" || exit 1
timeout 15 /usr/bin/ddcutil setvcp 60 0x13 --bus "$BUS"
