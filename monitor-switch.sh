#!/bin/bash
# Triggered by 99-usb-switch.rules when the UGREEN KVM hub (05e3:0626) is
# plugged into / unplugged from this Linux machine.
#   add    -> KVM pointed at Linux   -> BenQ input -> DisplayPort (bus 1, 0x0f)
#   remove -> KVM pointed at Windows -> BenQ input -> USB-C       (bus 1, 0x13)
#
# Bus 1 and the 0x13 USB-C value match the known-working manual shortcut
# (Ctrl+Alt+Home -> ddcutil setvcp 60 0x13 --bus 1). Bus 0 (used previously)
# has no monitor on it on this system/kernel - ddcutil detect only finds the
# BenQ on /dev/i2c-1. I2C bus numbers for DDC are assigned by DRM connector
# enumeration order and can shift across kernel/driver upgrades.

ACTION="$1"
LOG=/tmp/usb_switch.log
BUS=1

# No sleep here: the DDC/I2C link to the monitor is independent of the USB
# peripheral tree the KVM hub sits on, so there is nothing to "settle" before
# calling ddcutil. (The old 2s sleep was pure added latency - it did not
# account for the actual Windows->Linux delay, which is unrelated USB HID
# re-enumeration on a different hub.)

# GNOME session details for gdctl (see below). This script runs as root from
# udev, with none of the desktop's environment, so DBUS_SESSION_BUS_ADDRESS
# and XDG_RUNTIME_DIR must be supplied explicitly - confirmed sufficient by
# testing `env -i` with only these two vars set.
GNOME_USER=aananth
GNOME_UID=1000
gdctl_as_user() {
  /usr/sbin/runuser -u "$GNOME_USER" -- env \
    XDG_RUNTIME_DIR="/run/user/$GNOME_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$GNOME_UID/bus" \
    /usr/bin/gdctl set "$@"
}

case "$ACTION" in
  add)    INPUT=0x0f ;;
  remove) INPUT=0x13 ;;
  *)
    echo "$(date) monitor-switch.sh: unknown action '$ACTION', ignoring" >> "$LOG"
    exit 1
    ;;
esac

echo "$(date) UGREEN $ACTION detected, switching BenQ (bus $BUS) to $INPUT" >> "$LOG"
/usr/bin/ddcutil setvcp 60 "$INPUT" --bus "$BUS" >> "$LOG" 2>&1

if [ "$ACTION" = "add" ]; then
  # The Samsung (DP-5, MST off the BenQ's DP-out through an active DP->HDMI
  # converter) frequently stays powered off after this switch even though
  # mutter still reports it connected - a link/HPD re-negotiation the
  # converter doesn't complete on its own. Dropping and re-adding it from the
  # logical monitor layout forces mutter to redo that negotiation, which is
  # confirmed to revive it (same effect as the monitor's physical power
  # button, done in software). Positions match the current GNOME layout
  # (DP-2 primary at 2560,0 next to DP-5 at 0,0) - update these if the
  # desktop layout is ever rearranged.
  echo "$(date) reviving Samsung (DP-5) via gdctl" >> "$LOG"
  gdctl_as_user --logical-monitor --monitor DP-2 --primary --x 2560 --y 0 >> "$LOG" 2>&1
  sleep 1
  gdctl_as_user --logical-monitor --monitor DP-2 --primary --x 2560 --y 0 \
                --logical-monitor --monitor DP-5 --x 0 --y 0 >> "$LOG" 2>&1
fi
