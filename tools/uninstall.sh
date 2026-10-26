#!/bin/sh
# Remove the devkit from the Kindle: boot hook, Amazon block, disabled services, clock/time zone changes, and /mnt/us/kindle4ever.
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
  if [ -f /etc/rc5.d/.k4-disabled ]; then
    while read name target; do ln -sf \"\$target\" \"/etc/rc5.d/\$name\" && echo \"restored \$name\"; done < /etc/rc5.d/.k4-disabled
    rm /etc/rc5.d/.k4-disabled
  fi
  [ -f /etc/sysconfig/ntp.k4-orig ] && mv /etc/sysconfig/ntp.k4-orig /etc/sysconfig/ntp && echo 'amazon clock sync restored'
  [ -f /etc/TZ.k4-orig ] && mv /etc/TZ.k4-orig /etc/TZ && rm -f /var/local/system/tz && echo 'time zone restored (UTC)'
  [ -f /etc/profile.k4-orig ] && mv /etc/profile.k4-orig /etc/profile
  if [ -f /etc/kdb.k4-orig ]; then
    . /etc/kdb.k4-orig; kdb set system/daemon/powerd/t1_timeout \"\$t1_timeout\"; kdb set system/daemon/powerd/t2_timeout \"\$t2_timeout\"
    rm /etc/kdb.k4-orig; echo 'powerd timers restored'
  fi
  sync"
tools/k4 sh 'rm -f /mnt/us/DONT_START_FRAMEWORK' && echo "Amazon's UI starts at boot again"
[ $KEEP = 1 ] || { tools/k4 sh "rm -rf $D" && echo "$D removed"; }
echo "done (reboot to stop boot.sh and bring the disabled services back)"
