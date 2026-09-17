#!/bin/bash
# Installs the BenQ manual-switch scripts + Samsung MST auto-revive service
# from this repo onto the system. Re-run this after a fresh Ubuntu install /
# reformat, or after pulling repo changes, to restore the working setup
# documented in README.md.
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

for cmd in gdctl gdbus; do
  command -v "$cmd" >/dev/null 2>&1 || echo "Warning: '$cmd' not found on PATH - samsung-revive.sh/samsung-watch.sh need it." >&2
done

GNOME_USER=aananth
GNOME_UID=1000
run_as_gnome_user() {
  runuser -u "$GNOME_USER" -- env \
    XDG_RUNTIME_DIR="/run/user/$GNOME_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$GNOME_UID/bus" \
    "$@"
}

echo "Installing BenQ input-switch scripts -> /usr/local/bin"
install -o root -g root -m 755 "$SCRIPT_DIR/benq-sw-2-dp.sh" /usr/local/bin/benq-sw-2-dp.sh
install -o root -g root -m 755 "$SCRIPT_DIR/benq-sw-2-usb.sh" /usr/local/bin/benq-sw-2-usb.sh
install -o root -g root -m 755 "$SCRIPT_DIR/benq-sw-2-hdmi.sh" /usr/local/bin/benq-sw-2-hdmi.sh
install -o root -g root -m 755 "$SCRIPT_DIR/detect-benq-bus.sh" /usr/local/bin/detect-benq-bus.sh

echo "Installing samsung-revive.sh -> /usr/local/bin/samsung-revive.sh"
install -o root -g root -m 755 "$SCRIPT_DIR/samsung-revive.sh" /usr/local/bin/samsung-revive.sh

echo "Installing samsung-watch.sh -> /usr/local/bin/samsung-watch.sh"
install -o root -g root -m 755 "$SCRIPT_DIR/samsung-watch.sh" /usr/local/bin/samsung-watch.sh

echo "Installing samsung-watch-display.service (systemd --user unit)"
install -o root -g root -m 644 "$SCRIPT_DIR/samsung-watch-display.service" /etc/systemd/user/samsung-watch-display.service
run_as_gnome_user systemctl --user daemon-reload
run_as_gnome_user systemctl --user enable --now samsung-watch-display.service

cat <<'EOF'

Done.

BenQ input switching is manual - bind these to GNOME keyboard shortcuts
yourself (Settings -> Keyboard -> Custom Shortcuts; not stored in this repo,
back up with `dconf dump /org/gnome/settings-daemon/` if you want them to
survive a reformat):
  Ctrl+Alt+Home -> /usr/local/bin/benq-sw-2-dp.sh   (DisplayPort-1, Linux PC)
  Ctrl+Alt+End  -> /usr/local/bin/benq-sw-2-usb.sh  (USB-C, Windows PC)
  (unbound)     -> /usr/local/bin/benq-sw-2-hdmi.sh (HDMI-1)

samsung-watch-display.service is now running as a systemd --user service and
will automatically run samsung-revive.sh whenever DP-5 reappears in mutter.
Check status with `systemctl --user status samsung-watch-display.service`,
log at /tmp/watch_samsung.log.
EOF
