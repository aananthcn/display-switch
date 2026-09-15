#!/bin/bash
# Switch the BenQ GW2790QT (bus 1) to DisplayPort-1 input (the Linux PC).
# Bound to Ctrl+Alt+Home as a GNOME custom keyboard shortcut.
timeout 15 /usr/bin/ddcutil setvcp 60 0x0f --bus 1
