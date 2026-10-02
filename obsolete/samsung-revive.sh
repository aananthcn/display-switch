#!/bin/bash
# Re-links the Samsung (DP-5, MST branch off the BenQ's DP-out) via gdctl,
# without going through a KVM switch. Run this yourself after DP-5 is
# registered with mutter but still showing nothing - e.g. after pressing
# the Samsung's power button, or after an AC power-cycle (must be off for
# at least ~90s - its DC regulator's capacitance keeps it "on" for close to
# a minute otherwise, so a shorter cycle is as good as no cycle at all).
#
# Also called by samsung-watch.sh when DP-5 transitions from absent to
# present in mutter's topology (see that script).
#
# Usage: ./samsung-revive.sh
set -euo pipefail

# See obsolete/monitor-switch.sh's 2026-09-15 incident note: a wedged
# nvidia_modeset KMS thread can make gdctl's DBus calls to mutter hang
# indefinitely. Bound every call so this script fails fast instead of
# hanging when run standalone or from samsung-watch.sh.
GDCTL_TIMEOUT=5

# Connector names (DP-2/DP-4/DP-5...) are assigned by the driver and change
# across boots and kernel/driver updates, so never hardcode them. Resolve by
# identity from gdctl's top-level "Monitors:" section instead: the Samsung is
# vendor SAM, the BenQ is whatever other monitor is listed.
# Prints "<connector> <vendor>" per monitor.
list_monitors() {
  timeout "$GDCTL_TIMEOUT" /usr/bin/gdctl show 2>/dev/null | awk '
    /^Logical monitors:/ { exit }
    match($0, /Monitor [^ ]+ \(/) { name = substr($0, RSTART + 8, RLENGTH - 10) }
    /Vendor:/ { print name, $NF }'
}

# Sets SAMSUNG and BENQ; retries while the Samsung hasn't registered yet.
find_monitors() {
  local tries="$1" out
  for _ in $(seq 1 "$tries"); do
    out=$(list_monitors)
    SAMSUNG=$(awk '$2 == "SAM" { print $1; exit }' <<<"$out")
    BENQ=$(awk '$2 != "SAM" { print $1; exit }' <<<"$out")
    [ -n "$SAMSUNG" ] && [ -n "$BENQ" ] && return 0
    sleep 0.5
  done
  return 1
}

if ! find_monitors 4; then
  echo "Samsung and/or BenQ not registered with mutter (saw: ${SAMSUNG:-no Samsung}, ${BENQ:-no BenQ}) - gdctl can't fix this on its own." >&2
  echo "Press the Samsung's power button, or power-cycle it (off >=90s), first." >&2
  exit 1
fi

echo "Reviving Samsung ($SAMSUNG, BenQ $BENQ) via gdctl..."
# Solo BenQ must sit at (0,0) - mutter rejects a logical-monitor layout
# whose origin isn't (0,0) ("Logical monitors positions are offset").
# Positions below match the current GNOME layout (BenQ primary at 2560,0
# next to the Samsung at 0,0) - update if the desktop layout is rearranged.
timeout "$GDCTL_TIMEOUT" /usr/bin/gdctl set --logical-monitor --monitor "$BENQ" --primary --x 0 --y 0
sleep 1
timeout "$GDCTL_TIMEOUT" /usr/bin/gdctl set --logical-monitor --monitor "$BENQ" --primary --x 2560 --y 0 \
                    --logical-monitor --monitor "$SAMSUNG" --x 0 --y 0
echo "Done."
