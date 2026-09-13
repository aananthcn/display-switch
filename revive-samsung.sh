#!/bin/bash
# Re-links the Samsung (DP-5, MST branch off the BenQ's DP-out) via gdctl,
# without going through a KVM switch. Run this yourself after DP-5 is
# registered with mutter but still showing nothing - e.g. after pressing
# the Samsung's power button, or after an AC power-cycle (must be off for
# at least ~90s - its DC regulator's capacitance keeps it "on" for close to
# a minute otherwise, so a shorter cycle is as good as no cycle at all).
#
# Also called by monitor-switch.sh (via runuser, as this same user) after a
# KVM switch to Linux, when DP-5 is already registered but blank.
#
# Usage: ./revive-samsung.sh
set -euo pipefail

wait_for_monitor() {
  local name="$1" tries="$2"
  for _ in $(seq 1 "$tries"); do
    /usr/bin/gdctl show 2>/dev/null | grep -q "Monitor $name" && return 0
    sleep 0.5
  done
  return 1
}

if ! wait_for_monitor DP-5 4; then
  echo "DP-5 is not registered with mutter - gdctl can't fix this on its own." >&2
  echo "Press the Samsung's power button, or power-cycle it (off >=90s), first." >&2
  exit 1
fi

echo "Reviving Samsung (DP-5) via gdctl..."
# Solo DP-2 must sit at (0,0) - mutter rejects a logical-monitor layout
# whose origin isn't (0,0) ("Logical monitors positions are offset").
# Positions below match the current GNOME layout (DP-2 primary at 2560,0
# next to DP-5 at 0,0) - update these if the desktop layout is ever
# rearranged (check with `gdctl show -v`).
/usr/bin/gdctl set --logical-monitor --monitor DP-2 --primary --x 0 --y 0
sleep 1
/usr/bin/gdctl set --logical-monitor --monitor DP-2 --primary --x 2560 --y 0 \
                    --logical-monitor --monitor DP-5 --x 0 --y 0
echo "Done."
