#!/bin/bash
# Switch the BenQ GW2790QT (bus 1) to HDMI-1 input.
timeout 15 /usr/bin/ddcutil setvcp 60 0x11 --bus 1
