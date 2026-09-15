#!/bin/bash
# Switch the BenQ GW2790QT (bus 1) to USB-C input (the Windows PC).
# Bound to Ctrl+Alt+End as a GNOME custom keyboard shortcut.
timeout 15 /usr/bin/ddcutil setvcp 60 0x13 --bus 1
