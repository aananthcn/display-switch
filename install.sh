#!/bin/bash
# Installs the KVM -> DDC monitor-switching automation from this repo onto
# the system. Re-run this after a fresh Ubuntu install / reformat to restore
# the working setup documented in this repo.
#
# Usage: sudo ./install.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this with sudo: sudo ./install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v ddcutil >/dev/null 2>&1; then
  echo "ddcutil not found - installing..."
  apt-get update
  apt-get install -y ddcutil
fi

for cmd in gdctl runuser udevadm; do
  command -v "$cmd" >/dev/null 2>&1 || echo "Warning: '$cmd' not found on PATH - monitor-switch.sh needs it." >&2
done

echo "Installing monitor-switch.sh -> /usr/local/bin/monitor-switch.sh"
install -o root -g root -m 755 "$SCRIPT_DIR/monitor-switch.sh" /usr/local/bin/monitor-switch.sh
rm -f /usr/local/bin/switch2win.sh  # old name from before the rename

echo "Installing 99-usb-switch.rules -> /etc/udev/rules.d/99-usb-switch.rules"
install -o root -g root -m 644 "$SCRIPT_DIR/99-usb-switch.rules" /etc/udev/rules.d/99-usb-switch.rules

echo "Verifying udev rule..."
udevadm verify /etc/udev/rules.d/99-usb-switch.rules

# Reloading rules + retriggering is sufficient to pick up the new rule/script
# without a full systemd-udevd restart, which would briefly disrupt all
# device handling on the system.
echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

cat <<'EOF'

Done. Unplug/replug the UGREEN KVM hub (or flip it to the other PC and back)
to trigger a real switch event and confirm it works. Log: /tmp/usb_switch.log

Note: the GNOME custom keybinding "Switch Windows" (Ctrl+Alt+Home ->
ddcutil setvcp 60 0x13 --bus 1) is a manual fallback stored in GNOME's
dconf settings, not a file in this repo - it will NOT survive a reformat
unless backed up separately (e.g. `dconf dump /org/gnome/settings-daemon/`
or `dconf dump /` and restore with `dconf load`).
EOF
