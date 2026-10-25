#!/bin/sh
# Remove the devkit from the Kindle: boot hook, Amazon block, and /mnt/us/kindle4ever.
#   tools/uninstall.sh [--keep-files]   --keep-files leaves /mnt/us/kindle4ever in place
# Doesn't touch USBNetwork or the jailbreak (they have their own uninstallers).
# Reboot afterwards to stop a running boot.sh.
set -e
. "$(dirname "$0")/lib/env.sh"
cd "$K4_ROOT"
D=$K4_DEVICE_DIR
KEEP=0; [ "$1" = "--keep-files" ] && KEEP=1
tools/k4 sh "set -e; mntroot rw >/dev/null
  trap 'mntroot ro >/dev/null' EXIT
  rm -f /etc/rc5.d/S97k4-boot /etc/init.d/k4-boot && echo 'boot hook removed'
  if grep -q '^# >>> kindle4ever amazon-block' /etc/hosts; then
    sed '/^# >>> kindle4ever amazon-block/,/^# <<< kindle4ever amazon-block/d' /etc/hosts > /tmp/hosts.new
    cp /tmp/hosts.new /etc/hosts; rm /tmp/hosts.new; echo 'amazon block removed'
  fi
  sync"
[ $KEEP = 1 ] || { tools/k4 sh "rm -rf $D" && echo "$D removed"; }
echo "done (reboot to stop boot.sh if it's running)"
