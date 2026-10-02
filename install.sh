#!/bin/bash
# Installs the BenQ manual-switch scripts and the GT 710 nouveau loader from
# this repo onto the system. Re-run after a fresh Ubuntu install / reformat,
# or after pulling repo changes, to restore the setup documented in README.md.
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

# ddcutil needs /dev/i2c-* (bus numbers for the GT 710's nouveau connectors).
echo i2c-dev > /etc/modules-load.d/i2c-dev.conf
modprobe i2c-dev || true

echo "Installing BenQ input-switch scripts -> /usr/local/bin"
install -o root -g root -m 755 "$SCRIPT_DIR/benq-sw-2-hdmi.sh" /usr/local/bin/benq-sw-2-hdmi.sh
install -o root -g root -m 755 "$SCRIPT_DIR/benq-sw-2-usb.sh" /usr/local/bin/benq-sw-2-usb.sh
install -o root -g root -m 755 "$SCRIPT_DIR/detect-benq-bus.sh" /usr/local/bin/detect-benq-bus.sh

echo "Installing nouveau-gt710.service (loads nouveau at boot)"
install -o root -g root -m 644 "$SCRIPT_DIR/nouveau-gt710.service" /etc/systemd/system/nouveau-gt710.service
systemctl daemon-reload
systemctl enable nouveau-gt710.service

# Leftovers from the RTX-5070 / MST configuration (see obsolete/).
rm -f /usr/local/bin/benq-sw-2-dp.sh /usr/local/bin/samsung-revive.sh /usr/local/bin/samsung-watch.sh
if [ -e /etc/systemd/user/samsung-watch-display.service ]; then
  rm -f /etc/systemd/user/samsung-watch-display.service
  echo "Removed samsung-watch-display.service. As your user, also run:"
  echo "  systemctl --user disable --now samsung-watch-display.service"
fi

cat <<'EOT'

Done.

BenQ input switching is manual - bind these to GNOME keyboard shortcuts
yourself (Settings -> Keyboard -> Custom Shortcuts):
  Ctrl+Alt+Home -> /usr/local/bin/benq-sw-2-hdmi.sh (HDMI-1, Linux PC)
  Ctrl+Alt+End  -> /usr/local/bin/benq-sw-2-usb.sh  (USB-C, Windows PC)
EOT
