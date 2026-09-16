# display-switch

BenQ GW2790QT input switching on host `parasivam`, driven manually via
keyboard shortcuts instead of automatically off KVM USB events.

## Why manual

The previous setup (`obsolete/99-usb-switch.rules` + `obsolete/monitor-switch.sh`)
switched the BenQ's DDC/CI input automatically on udev USB add/remove events
from the UGREEN KVM hub. Every DDC/CI-triggered input switch (`setvcp 60`)
makes the BenQ's scaler reinitialize and retrain its DisplayPort link, which
briefly drops video on both the BenQ and the Samsung (MST-chained off the
BenQ's DP-out) - `gnome-shell: Failed to create KMS output: No modes
available` until the link retrains and mutter rediscovers it. Switching via
the monitor's own OSD buttons doesn't cause this. A DDC "power on" (VCP
0xD6=0x01) nudge after the switch was tried and didn't fix it (see git
history / `obsolete/monitor-switch.sh`'s comments for the full investigation,
including a separate NVIDIA driver KMS-wedge bug found along the way).

Given the retrain appears to be inherent to a DDC/CI-triggered input switch
on this monitor, the fix is to switch input manually via GNOME keyboard
shortcuts instead of tapping USB hotplug events - same trade-off as OSD
buttons, without leaving the keyboard.

## Scripts

- `benq-sw-2-dp.sh` - switch BenQ to DisplayPort-1 (Linux PC)
- `benq-sw-2-usb.sh` - switch BenQ to USB-C (Windows PC)
- `benq-sw-2-hdmi.sh` - switch BenQ to HDMI-1

All three just run `ddcutil setvcp 60 <value> --bus 1` (bus 1 and the VCP
values are specific to this BenQ GW2790QT unit - re-verify with `ddcutil
detect` / `ddcutil capabilities --bus 1` after any kernel/NVIDIA driver
upgrade, since DDC-over-I2C bus numbers are assigned by DRM connector
enumeration order and are not guaranteed stable). No sudo needed - run as
the normal desktop user (in the `i2c` group).

Installed to `/usr/local/bin` (same pattern as `samsung-revive.sh`/
`samsung-watch.sh`) so GNOME shortcuts have a stable path independent of
where this repo checkout lives:

```
sudo cp benq-sw-2-dp.sh benq-sw-2-usb.sh benq-sw-2-hdmi.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/benq-sw-2-dp.sh /usr/local/bin/benq-sw-2-usb.sh /usr/local/bin/benq-sw-2-hdmi.sh
```

## GNOME shortcuts

Configured manually in Settings -> Keyboard -> Custom Shortcuts (not stored
in this repo - back up with `dconf dump /org/gnome/settings-daemon/` if you
want this to survive a reformat):

- `Ctrl+Alt+Home` -> `/usr/local/bin/benq-sw-2-dp.sh`
- `Ctrl+Alt+End` -> `/usr/local/bin/benq-sw-2-usb.sh`

## Samsung (DP-5) auto-revive - still active, unrelated to the above

`samsung-revive.sh` and `samsung-watch.sh` (installed as `samsung-watch-display.service`,
a systemd --user unit) handle a separate problem: the Samsung, MST-chained
off the BenQ's DP-out, frequently needs its logical-monitor position
re-poked via `gdctl` to actually show video after it reappears (e.g. after
its own power button is pressed, or an AC power-cycle of >=90s). This is
independent of how the BenQ's input is switched and is left running as-is.
Check status with `systemctl --user status samsung-watch-display.service`, log at
`/tmp/watch_samsung.log`.

## obsolete/

The previous fully-automated udev-based approach, kept for reference/history
- see `obsolete/README.md` for the original topology writeup and full
incident history (I2C bus renumbering, double-firing udev rules, the
NVIDIA KMS-wedge bug, etc).

# Windows Shortcut
Created a link file in Desktop and mapped it to Ctrl+Alt+Home with following as command:
C:\_D\Tools\my-tools\ControlMyMonitor.exe /SetValue Primary 60 16
