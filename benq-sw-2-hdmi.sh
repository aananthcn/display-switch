#!/bin/bash
# Switch the BenQ GW2790QT to HDMI-1 input.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUS="$("$SCRIPT_DIR/detect-benq-bus.sh")" || exit 1
timeout 15 /usr/bin/ddcutil setvcp 60 0x11 --bus "$BUS"
