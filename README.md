# display-switch

BenQ GW2790QT input switching on host `parasivam`, driven manually via
keyboard shortcuts.

## Current topology (GT 710 for graphics, RTX 5070 for AI only)

The Gigabyte GT 710 (nouveau) drives both monitors directly: BenQ on HDMI,
Samsung on DVI-D (via a DVI-to-HDMI cable). No DisplayPort, no MST. The
RTX 5070 has no displays attached and is used only for AI work.

nouveau is blacklisted by the NVIDIA package (`blacklist nouveau`, `alias
nouveau off`), so `nouveau-gt710.service` loads it at boot: it modprobes the
dependencies, then `insmod`s the .ko directly (plain `insmod` alone fails
with "Unknown symbol drm_dp_..." because it skips dependencies).

**Verified:** after a reboot, `nouveau-gt710.service` loads nouveau at boot and
both monitors come up on the GT 710.

Limits of the GT 710: DVI-D is single-link (max 1920x1200@60), HDMI 1.4
(max 4K@30). If the Samsung is a 1440p panel it will run at 1080p/1200p.

## History: why manual switching

The earlier setup (`obsolete/99-usb-switch.rules` + `obsolete/monitor-switch.sh`)
switched the BenQ's DDC/CI input automatically on udev USB add/remove events
from the UGREEN KVM hub. With the RTX 5070 on DisplayPort and the Samsung
MST-chained off the BenQ, every DDC/CI input switch forced a DP link retrain
that dropped both monitors. Switching manually via keyboard shortcuts was the
workaround. The MST chain and its Samsung auto-revive scripts
(`obsolete/samsung-*`) are no longer used.

## Scripts

- `benq-sw-2-hdmi.sh` - switch BenQ to HDMI-1 (Linux PC, VCP 60 = 0x11)
- `benq-sw-2-usb.sh` - switch BenQ to USB-C (Windows PC, VCP 60 = 0x13)
- `detect-benq-bus.sh` - finds the BenQ's I2C bus by name (bus numbers shift)
- `nouveau-gt710.service` - loads nouveau at boot
- `install.sh` - installs all of the above (`sudo ./install.sh`), enables
  `i2c-dev`, and removes the old DP/Samsung leftovers

VCP values are specific to this BenQ unit - re-verify with `ddcutil
capabilities --bus <N>` after a kernel/driver upgrade. No sudo needed at run
time; the user must be in the `i2c` group.

## GNOME shortcuts

Configured manually in Settings -> Keyboard -> Custom Shortcuts (back up with
`dconf dump /org/gnome/settings-daemon/`):

- `Ctrl+Alt+Home` -> `/usr/local/bin/benq-sw-2-hdmi.sh`
- `Ctrl+Alt+End` -> `/usr/local/bin/benq-sw-2-usb.sh`

If the old `samsung-watch-display.service` is still enabled, run
`systemctl --user disable --now samsung-watch-display.service`.

## obsolete/

The previous RTX-5070 / DisplayPort / MST setup, kept for history. See
`obsolete/README.md` for the original topology writeup and incident history.

# Windows Shortcut
Created a link file in Desktop and mapped it to Ctrl+Alt+Home with following as command:
C:\_D\Tools\my-tools\ControlMyMonitor.exe /SetValue Primary 60 16

This would choose USB-C as input.

Created another link file for Switch2Linux and mapped it to Ctrl+Home+End with following as command:
C:\_D\Tools\my-tools\ControlMyMonitor.exe /SetValue Primary 60 17

This would choose HDMI-1 as input (VCP 60 value 0x11 = 17, same as benq-sw-2-hdmi.sh on the Linux side). It was 15 (DisplayPort) in the old configuration - update the Windows shortcut.
