#!/bin/bash
# Watches mutter's MonitorsChanged D-Bus signal and automatically runs
# revive-samsung.sh when DP-5 (Samsung) transitions from absent to present
# in mutter's topology - e.g. after pressing the Samsung's power button, or
# an AC power-cycle (off >=90s). Removes the need to manually run
# revive-samsung.sh afterwards; the physical button/power-cycle action is
# still the only known way to trigger the transition itself (see README's
# "Open problem" section).
#
# Runs as a systemd --user service (watch-samsung.service) so it has the
# normal desktop session's D-Bus access without any runuser/env tricks -
# unlike monitor-switch.sh, which is invoked by udev as root and has none
# of that for free.
#
# DP-5 stays listed under gdctl show's top-level "Monitors:" section
# throughout revive-samsung.sh's own disable/re-add dance (only the
# "Logical monitors:" section changes), so this loop does not mistake its
# own gdctl calls for a fresh hotplug and re-trigger itself.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/tmp/watch_samsung.log

is_dp5_present() {
  /usr/bin/gdctl show 2>/dev/null | grep -q "Monitor DP-5"
}

was_present=false
is_dp5_present && was_present=true

echo "$(date) watch-samsung.sh started (DP-5 initially $([ "$was_present" = true ] && echo present || echo absent))" >> "$LOG"

/usr/bin/gdbus monitor --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig 2>>"$LOG" |
while IFS= read -r line; do
  case "$line" in
    *MonitorsChanged*)
      is_present=false
      is_dp5_present && is_present=true
      if [ "$is_present" = true ] && [ "$was_present" = false ]; then
        echo "$(date) DP-5 appeared, reviving via revive-samsung.sh" >> "$LOG"
        "$SCRIPT_DIR/revive-samsung.sh" >> "$LOG" 2>&1
      fi
      was_present="$is_present"
      ;;
  esac
done
