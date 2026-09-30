#!/bin/bash
# Watches mutter's MonitorsChanged D-Bus signal and automatically runs
# samsung-revive.sh when DP-5 (Samsung) transitions from absent to present
# in mutter's topology - e.g. after pressing the Samsung's power button, or
# an AC power-cycle (off >=90s). Removes the need to manually run
# samsung-revive.sh afterwards; the physical button/power-cycle action is
# still the only known way to trigger the transition itself (see README's
# "Open problem" section).
#
# Runs as a systemd --user service (samsung-watch-display.service) so it has the
# normal desktop session's D-Bus access without any runuser/env tricks -
# unlike the old udev-triggered monitor-switch.sh (see obsolete/), which ran
# as root and had none of that for free.
#
# DP-5 stays listed under gdctl show's top-level "Monitors:" section
# throughout samsung-revive.sh's own disable/re-add dance (only the
# "Logical monitors:" section changes), so this loop does not mistake its
# own gdctl calls for a fresh hotplug and re-trigger itself.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/tmp/watch_samsung.log

is_dp5_present() {
  /usr/bin/gdctl show 2>/dev/null | grep -q "Vendor: SAM"
}

# The still-unsolved NVIDIA KMS/MST wedge (obsolete/README.md "Open problem"
# section) doesn't always go through a clean absent->present DP-5 transition
# - sometimes it just stalls the whole KMS atomic-commit pipeline instead
# (gnome-shell spams "Page flip failed"/"Failed to post KMS update" every
# frame, no MonitorsChanged signal, no kernel/nvidia log lines at all). That
# leaves no record anywhere unless you happen to go digging in journalctl
# afterwards. Tag it into this log too so it's visible next to the DP-5
# revive history. Debounced to one note per 30s so the frame-rate spam
# doesn't flood the log; this only logs a note, it doesn't attempt a fix -
# manual OSD/cable changes and gdctl are confirmed not to help once this
# state is hit, only a reboot (or the Samsung's own >=90s power-cycle, if
# that's what triggers the underlying MST retrain) has recovered it so far.
watch_kms_wedge() {
  local last=0 now
  journalctl -f -o cat -t gnome-shell 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *"Failed to post KMS update"*)
        now=$(date +%s)
        if (( now - last >= 30 )); then
          echo "$(date) KMS/MST wedge detected (drmModeAtomicCommit spam from gnome-shell) - manual input-switch/cable changes won't fix this, see obsolete/README.md 'Open problem' section; try a reboot" >> "$LOG"
          last=$now
        fi
        ;;
    esac
  done
}
watch_kms_wedge &

was_present=false
is_dp5_present && was_present=true

echo "$(date) samsung-watch.sh started (DP-5 initially $([ "$was_present" = true ] && echo present || echo absent))" >> "$LOG"

/usr/bin/gdbus monitor --session --dest org.gnome.Mutter.DisplayConfig \
  --object-path /org/gnome/Mutter/DisplayConfig 2>>"$LOG" |
while IFS= read -r line; do
  case "$line" in
    *MonitorsChanged*)
      is_present=false
      is_dp5_present && is_present=true
      if [ "$is_present" = true ] && [ "$was_present" = false ]; then
        echo "$(date) DP-5 appeared, reviving via samsung-revive.sh" >> "$LOG"
        "$SCRIPT_DIR/samsung-revive.sh" >> "$LOG" 2>&1
      fi
      was_present="$is_present"
      ;;
  esac
done
