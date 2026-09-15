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

# 2026-09-15 incident: an nvidia_modeset kernel NULL-pointer BUG
# (DisplayPort::ConnectorImpl::ensureMstNodesPoweredUp) wedged the KMS
# thread mid-DDC-switch, which in turn wedges ddcutil's I2C-over-DP-AUX
# channel and gdctl's DBus calls to mutter indefinitely. Without a timeout,
# each hung invocation sat until udev's own 180s RUN+= kill, and every KVM
# hub bounce in the meantime spawned another one on top of it, eating
# systemd-udevd's worker pool and stalling unrelated USB hotplug (e.g.
# flashing a Qualcomm board) behind it. DDCUTIL_TIMEOUT/GDCTL_TIMEOUT below
# fail fast instead, and the lock below stops the pileup. This doesn't fix
# the underlying nvidia driver bug - see README - it just stops one wedged
# switch from cascading into unrelated USB failures.
DDCUTIL_TIMEOUT=15
GDCTL_TIMEOUT=5
REVIVE_TIMEOUT=20

LOCK=/run/lock/monitor-switch.lock
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "$(date) monitor-switch.sh: another instance is still running (likely wedged on I2C/DBus) - skipping this event instead of piling up" >> "$LOG"
  exit 0
fi

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_as_user() {
  local t="$1"; shift
  timeout "$t" /usr/sbin/runuser -u "$GNOME_USER" -- env \
    XDG_RUNTIME_DIR="/run/user/$GNOME_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$GNOME_UID/bus" \
    "$@"
}

# The BenQ's own DisplayPort link briefly drops and retrains when its OSD
# input is switched (its scaler reinitializing) - mutter takes a moment to
# rediscover DP-2 afterwards. Calling gdctl before that finishes fails with
# "Monitor DP-2 not found" (seen in testing), so poll for it instead of
# guessing a fixed delay. Also used to wait for DP-5 (Samsung) - see below,
# which has two distinct failure modes, not one:
#   1. DP-5 stays registered with mutter but shows nothing - the
#      disable/re-add dance below fixes this (confirmed repeatedly).
#   2. DP-5 drops out of mutter's topology entirely ("Monitor DP-5 not
#      found" from gdctl) - nothing gdctl does can help, since it can only
#      rearrange monitors mutter already knows about. So far only a manual
#      press of the Samsung's own power button has been observed to bring
#      it back into mutter's topology (after which case 1's fix applies).
wait_for_monitor() {
  local name="$1" tries="$2"
  for _ in $(seq 1 "$tries"); do
    run_as_user "$GDCTL_TIMEOUT" /usr/bin/gdctl show 2>/dev/null | grep -q "Monitor $name" && return 0
    sleep 0.5
  done
  return 1
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
timeout "$DDCUTIL_TIMEOUT" /usr/bin/ddcutil setvcp 60 "$INPUT" --bus "$BUS" >> "$LOG" 2>&1
DDCUTIL_RC=$?
if [ "$DDCUTIL_RC" -eq 124 ]; then
  echo "$(date) ddcutil timed out after ${DDCUTIL_TIMEOUT}s (I2C/DP-AUX channel likely wedged) - giving up on this event, not polling gdctl (it's likely wedged too)" >> "$LOG"
  exit 1
fi

if [ "$ACTION" = "add" ]; then
  # 2026-09-15 experiment: unlike switching input via the BenQ's own OSD
  # buttons, a DDC/CI-triggered VCP 0x60 write is consistently followed by
  # a period where the GPU can't get KMS modes ("Failed to create KMS
  # output: No modes available" - see README) until the DP link retrains
  # and mutter rediscovers it. Hypothesis: the monitor's firmware treats a
  # DDC/CI input switch differently from a button-press input switch, and
  # is waiting for an explicit "power on" (VCP D6=0x01) the button path
  # sends implicitly. Testing whether nudging it ourselves shortens/avoids
  # that gap. If this doesn't measurably help, remove it - it's an added
  # DDC/CI write into the same AUX channel that's already prone to
  # wedging (see DDCUTIL_TIMEOUT note above), so it isn't free.
  sleep 1
  timeout "$DDCUTIL_TIMEOUT" /usr/bin/ddcutil setvcp d6 0x01 --bus "$BUS" >> "$LOG" 2>&1

  # The Samsung (DP-5, MST off the BenQ's DP-out through an active DP->HDMI
  # converter) frequently stays powered off after this switch. The actual
  # gdctl disable/re-add dance lives in revive-samsung.sh, shared with
  # manual invocation - see that file for the position/layout details.
  if wait_for_monitor DP-2 10; then
    if wait_for_monitor DP-5 20; then
      echo "$(date) DP-5 registered with mutter, reviving via revive-samsung.sh" >> "$LOG"
      run_as_user "$REVIVE_TIMEOUT" "$SCRIPT_DIR/revive-samsung.sh" >> "$LOG" 2>&1
    else
      echo "$(date) DP-5 never registered with mutter (MST branch fully dropped) - Samsung will likely need a manual power-button press this time" >> "$LOG"
    fi
  else
    echo "$(date) DP-2 did not reappear in time, skipping Samsung revive" >> "$LOG"
  fi
fi
