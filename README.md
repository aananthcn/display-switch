# KVM display-switch automation (host `parasivam`)

Automates switching the BenQ monitor's input (and thus the daisy-chained
Samsung monitor) between the Linux box and a Windows PC, driven by a UGREEN
USB-A KVM switch. Ubuntu 26.04, GNOME Shell 50 on Wayland, NVIDIA RTX 5070
(driver 595.91.07).

## If you're restoring this after a reformat / crash

```
sudo ./install.sh
```

This installs the two files below to their system locations, checks for
`ddcutil` (installs it via apt if missing), reloads udev, and prints a
reminder about the one piece of state this repo does *not* capture (the
GNOME manual-fallback keybinding — see below).

## Hardware topology

- **BenQ GW2790QT 27"** — connected to the Linux PC via DisplayPort, and to
  the Windows PC via USB-C/Thunderbolt. Its DDC/CI input-select (VCP feature
  `0x60`) determines which one is shown. VCP value `0x0f` = DisplayPort,
  `0x13` = USB-C.
- **Samsung U28E590 28" (4K, HDMI-only, 30Hz@4K panel)** — daisy-chained off
  the BenQ's DisplayPort-out via DisplayPort MST, through a **UGREEN active
  DP→HDMI adapter** (DP 1.2 in, HDMI 2.0 out), into the Samsung's HDMI2
  input. It shows up in Linux as its own real DRM/DP output (`DP-5`), not as
  a mirror of the BenQ — but its DDC/CI channel is *not* exposed as a
  separate `/dev/i2c-*` device, so `ddcutil` can only ever address the BenQ.
  Whatever happens to the Samsung is entirely driven by the video stream
  through that MST branch.
- **UGREEN USB-A KVM switch** (Genesys Logic hub, USB VID:PID `05e3:0626`) —
  moves keyboard/mouse between the two PCs. From Linux's perspective,
  pointing it at Linux fires a udev `add` event for the hub; pointing it at
  Windows fires `remove`.

## Files

| File | Installed to | Purpose |
|---|---|---|
| `99-usb-switch.rules` | `/etc/udev/rules.d/99-usb-switch.rules` | Matches the KVM hub's `add`/`remove` USB hotplug events and runs `monitor-switch.sh`. |
| `monitor-switch.sh` | `/usr/local/bin/monitor-switch.sh` | Switches the BenQ's DDC input via `ddcutil`, then (on `add` only) revives the Samsung via `gdctl`. Runs as root, non-interactively, from udev. |
| `install.sh` | — (run directly) | Installs both files above with correct ownership/permissions and reloads udev. Idempotent — safe to re-run. |

## Key findings (most-recent first)

### The Samsung sometimes doesn't come back after switching to Linux

**Symptom:** switching the KVM to Linux correctly flips the BenQ to
DisplayPort, but the Samsung stays fully powered off (not just blanked),
even though GNOME (`gdctl show` / xrandr) reports `DP-5` as connected and
active the whole time. Historically the only fix was pressing the Samsung's
physical power button.

**Ruled out:**
- Not a timing regression from removing the old 2s `sleep` in the script —
  confirmed to happen even with the old, slower script.
- Not the Samsung's Eco Saving Plus / Off Timer settings — both were already
  off.
- Samsung's OSD "Source Detection: Auto" (vs. the default "Manual") makes it
  visibly retry HDMI1 → HDMI2 → DisplayPort in a loop after a signal drop,
  but it never catches the Samsung's own port in time — the underlying link
  problem is upstream of what OSD auto-scan can fix.
- Not a DP bandwidth/resolution mismatch — checked via `gdctl show -v`; the
  Samsung's actual current mode (2560x1440@59.951, well under its native
  3840x2160@30 limit) isn't the issue.
- `xrandr --output DP-5 --off` **appears** to succeed (`exit 0`) but does
  nothing — this is a Wayland session (`XDG_SESSION_TYPE=wayland`), so
  `xrandr` only talks to Xwayland's compatibility shim, not the real
  mutter-managed output. Don't use xrandr for anything monitor-control
  related on this system; use `gdctl` (GNOME's own Wayland-native display
  CLI, ships with GNOME Shell 47+).

**There are actually two distinct failure modes**, discovered by comparing
`gdctl show` output live across repeated switch tests:

1. **`DP-5` stays registered with mutter, just shows nothing.** `gdctl show`
   still lists it as connected with a current mode. Forcibly dropping and
   re-adding it in mutter's logical monitor layout via `gdctl set` makes
   mutter redo the output negotiation in software — confirmed repeatedly to
   revive the picture, no physical button needed.
2. **`DP-5` disappears from mutter's topology entirely.** `gdctl show` lists
   only `DP-2`. `gdctl` cannot fix this — it can only rearrange monitors
   mutter already knows about, and there is nothing for it to re-add. This
   turned out to be the **more common** outcome of a real KVM switch in
   testing, not the exception. A 2-minute passive poll confirmed `DP-5`
   does not come back on its own — only pressing the Samsung's physical
   power button has reliably brought it back into mutter's topology (after
   which case 1's fix applies, since it comes back registered-but-blank).
   **This case is still unsolved from software alone — see "Open problem"
   below.**

`monitor-switch.sh` implements the automatic fix for case 1: it polls for
`DP-2` to reappear after the DDC switch (its own link briefly retrains when
the OSD input changes), then separately polls for `DP-5` to be registered,
and only then runs the drop/re-add. If `DP-5` never registers within the
poll window, it logs that clearly instead of silently failing, so you know
case 2 happened and a manual power-button press is needed that time.

Caveats:
- The gdctl revive runs on **every** switch to Linux where `DP-5` is
  registered, not just when it's actually blank (the script can't tell in
  advance) — so the Samsung will blank for about a second even on switches
  that would have been fine on their own.
- The `gdctl set` calls hardcode the current desktop layout (BenQ primary
  at `2560,0`, Samsung at `0,0`) and the connector names (`DP-2`, `DP-5`).
  If you ever rearrange the monitors in GNOME Settings, or a kernel/driver
  update renumbers the DRM connectors, update the `--x`/`--y` values and
  connector names in `monitor-switch.sh` to match — check with
  `gdctl show -v`.
- A solo remaining logical monitor must sit at `(0,0)` — mutter rejects any
  layout whose origin isn't `(0,0)` with "Logical monitors positions are
  offset". (Caused a real bug during development: the disable step used
  `--x 2560 --y 0` for solo `DP-2`, which always failed.)
- `gdctl` needs a real D-Bus session to talk to mutter. Since udev runs this
  script as root with no desktop environment, the script explicitly runs
  `gdctl` via `runuser -u aananth` with `XDG_RUNTIME_DIR=/run/user/1000` and
  `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus` set by hand.
  Confirmed these two vars are sufficient (tested with `env -i` plus just
  these two). If you change the Linux-side username/UID, update
  `GNOME_USER`/`GNOME_UID` at the top of `monitor-switch.sh`.

### Open problem: automatically recovering case 2 (`DP-5` fully dropped)

Unsolved. No script/CLI-level fix found; documenting the reasoning for
future reference.

**Why Windows doesn't have this problem (best understanding, can't inspect
the actual driver code):** DisplayPort MST — the protocol behind the
BenQ → converter → Samsung chain — lets a downstream branch device tell the
GPU "something changed, re-check my status" via a lightweight *sideband*
message on the shared AUX channel, without a full topology teardown. That's
what should happen when the Samsung's HDMI side blips during the BenQ's
input switch: a quick re-sync, not a disconnect. NVIDIA's Windows driver
evidently handles that sideband message correctly and just re-links the
branch. NVIDIA's **Linux** driver, at least in this combination (a plain
active DP→HDMI adapter acting as an MST branch, not a purpose-built
DisplayPort MST hub), appears to mishandle or drop that message — instead
of re-linking, it tears the branch out of the topology entirely, matching
exactly what's observed (`DP-5` vanishes rather than just going blank).
This lines up with NVIDIA's Linux driver having generally weaker/buggier
MST hotplug handling than its Windows counterpart — a known rough edge,
since Linux desktop MST usage gets far less QA attention than Windows.

**Why it can't be fixed from a script:** that decision is made inside the
closed-source kernel driver's AUX-channel interrupt handling. There is no
sysfs file, DRM property, `gdctl`/`xrandr` call, or other userspace hook
that lets a script re-inject "here's the sideband message you missed" or
otherwise force the driver to re-link an already-dropped MST branch.
Confirmed a 2-minute wait doesn't let it self-heal either.

**Options considered, none implemented yet:**
1. **Check for a newer NVIDIA driver.** Currently on 595.91.07. NVIDIA does
   periodically fix MST bugs; worth checking release notes / trying a
   driver update before assuming this needs a workaround at all.
2. **Smart plug to power-cycle the Samsung.** Cut and restore mains power
   to the Samsung via a WiFi/Zigbee smart plug (prefer a local-API one like
   Shelly/Tasmota over a cloud-only one) when `DP-5` doesn't register in
   time. A real electrical power-cycle is very likely to force the same
   fresh HPD the physical button does, since it re-initializes the
   monitor's HDMI receiver hardware from scratch. Needs ~$10-20 of hardware
   plus scripting its API into `monitor-switch.sh`. Most likely to actually
   work end-to-end; not yet built.
3. **Force a DRM connector reprobe via debugfs**
   (`/sys/kernel/debug/dri/.../force`, root-only) to see if that makes the
   NVIDIA driver rediscover the dropped branch without new hardware.
   Untested — uncertain whether NVIDIA's proprietary driver honors `force`
   for a dynamically-managed MST sub-connector the way it does for a real
   physical port.
4. **Accept it as semi-automatic.** Current state: the script auto-fixes
   case 1, clearly logs case 2 when it happens, and a manual power-button
   press remains the only known fix for case 2.

### Blank-screen regression after migrating 22.04 → 26.04

Three independent bugs were found, none of them an actual USB-matching
regression:

1. **Wrong I2C bus.** The script used bus `0`; `ddcutil detect` only finds
   the BenQ on `/dev/i2c-1`. DDC-over-I2C bus numbers are assigned by DRM
   connector enumeration order at driver load and can shift across
   kernel/NVIDIA driver upgrades — **re-run `ddcutil detect` after any such
   upgrade** before assuming anything else is broken.
2. **Double-firing udev rule.** The rule matched `SUBSYSTEM=="usb",
   ENV{PRODUCT}=="5e3/626/*"` with no `DEVTYPE` filter. `ENV{PRODUCT}` is
   present on both the `usb_device` node and its child `usb_interface`
   node, so the rule fired twice per physical event, racing two `ddcutil`
   calls on the same I2C bus. Fixed with `ENV{DEVTYPE}=="usb_device"`.
3. **Wrong VCP value on `remove`.** Both `add` and `remove` used to run the
   same script logic, always setting DisplayPort. `remove` (KVM back to
   Windows) needs `0x13` (USB-C), not `0x0f`.

**Follow-up:** on Ubuntu 26.04's systemd/udev 259, a bare `DEVTYPE==` match
key (without `ENV{}`) is **invalid** and silently drops the whole rule line
(`udevadm test` reports `Invalid key 'DEVTYPE'`) — always use
`ENV{DEVTYPE}==`. After editing udev rules, verify with
`udevadm verify <file>` and check `journalctl -u systemd-udevd` for
`Invalid key` warnings after `udevadm control --reload-rules && udevadm
trigger`.

## Manual fallback (not in this repo)

A GNOME custom keybinding named "Switch Windows", bound to `Ctrl+Alt+Home`,
runs `ddcutil setvcp 60 0x13 --bus 1` directly — the known-good reference
for the correct bus number and USB-C VCP value. It lives in GNOME's dconf
settings, **not** as a file here, so it will not survive a reformat unless
backed up separately, e.g.:

```
dconf dump /org/gnome/settings-daemon/ > keybinding-backup.dconf
# restore with: dconf load /org/gnome/settings-daemon/ < keybinding-backup.dconf
```

## Troubleshooting checklist

- Log: `/tmp/usb_switch.log` (written by `monitor-switch.sh`).
- `ddcutil detect` — confirms which `/dev/i2c-*` bus the BenQ answers on.
- `gdctl show -v` — confirms connector names, current modes, and logical
  monitor layout/positions as mutter sees them.
- `udevadm test /sys/...` or check `journalctl -u systemd-udevd` for rule
  errors after any udev rule edit.
- This is a **Wayland** session — don't use `xrandr` to diagnose or fix
  anything monitor-related; use `gdctl`.

## This repo is local-only

`git init` was run in this directory but nothing has been pushed to a
remote. If the disk this repo lives on is reformatted or fails, this
history is lost too — push it to a remote (GitHub/GitLab/etc.) if you want
it to actually survive that.
