#!/bin/bash
# Print the I2C bus number currently assigned to the BenQ GW2790QT.
#
# DDC-over-I2C bus numbers are assigned by DRM connector enumeration order,
# which is not guaranteed stable - it has shifted across kernel/driver
# upgrades and even across which monitors are connected at boot (e.g. bus 1
# with only the BenQ connected vs bus 2 once the Samsung MST chain is also
# up). Hardcoding --bus N in the switch scripts broke silently each time;
# this resolves it fresh on every invocation instead.
set -euo pipefail

bus="$(ddcutil detect --brief 2>/dev/null | awk '
  /I2C bus:/ { bus = $NF }
  /Monitor:.*BenQ GW2790QT/ { print bus; exit }
')"

if [[ -z "$bus" ]]; then
  echo "detect-benq-bus.sh: no BenQ GW2790QT found via ddcutil detect" >&2
  exit 1
fi

echo "${bus#/dev/i2c-}"
