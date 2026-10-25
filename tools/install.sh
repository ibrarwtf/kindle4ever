#!/bin/sh
# Install (or update) the devkit on a jailbroken Kindle 4 NT that has USBNetwork SSH working.
#   tools/install.sh [--amazon-block] [--no-boot-hook] [--start]
#     --amazon-block   add the Amazon-services block to /etc/hosts (device/rootfs/etc/hosts.amazon-block)
#     --no-boot-hook   don't install /etc/init.d/k4-boot (boot.sh won't run at boot)
#     --start          (re)start boot.sh now instead of waiting for the next reboot
# Safe to run again: it updates files in place. Build first: tools/build.sh
#
# Writes to the Kindle:
#   /mnt/us/kindle4ever/{bin,run}, boot.sh, VERSION        userstore (FAT), no root fs changes
#   /etc/init.d/k4-boot, /etc/rc5.d/S97k4-boot  root fs, via mntroot rw/ro (unless --no-boot-hook)
#   /etc/hosts (+ backup /etc/hosts.k4-orig)       only with --amazon-block
set -e
. "$(dirname "$0")/lib/env.sh"
cd "$K4_ROOT"
K=tools/k4
D=$K4_DEVICE_DIR
AMAZON=0 HOOK=1 START=0
for a in "$@"; do
  case "$a" in
    --amazon-block) AMAZON=1 ;;
    --no-boot-hook) HOOK=0 ;;
    --start) START=1 ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
  esac
done
for f in build/k4draw build/k4keys build/k4fetch; do [ -f "$f" ] || { echo "missing $f - run tools/build.sh" >&2; exit 1; }; done
. tools/lib/version.sh; VERSION=$(k4_version)

echo "== devkit files -> $D (version $VERSION)"
$K sh "mkdir -p $D/bin $D/run $D/apps"
$K deploy >/dev/null
$K push device/kindle4ever/boot.sh "$D/boot.sh"
printf '%s\n' "$VERSION" > build/VERSION.txt
$K push build/VERSION.txt "$D/VERSION"
# date of the devkit's last change (shown on the welcome screen): last commit, else now
{ git log -1 --format=%ct 2>/dev/null || date +%s; } > build/VERSION.txt
$K push build/VERSION.txt "$D/UPDATED"
rm -f build/VERSION.txt

if [ $HOOK = 1 ] || [ $AMAZON = 1 ]; then
  [ $HOOK = 1 ] && $K push device/rootfs/etc/init.d/k4-boot /tmp/k4-boot
  [ $AMAZON = 1 ] && $K push device/rootfs/etc/hosts.amazon-block /tmp/k4-hosts-block
  echo "== root fs (mntroot rw ... ro)"
  $K sh "set -e; mntroot rw >/dev/null
    trap 'mntroot ro >/dev/null' EXIT
    if [ -f /tmp/k4-boot ]; then
      cp /tmp/k4-boot /etc/init.d/k4-boot; chmod 755 /etc/init.d/k4-boot
      ln -sf ../init.d/k4-boot /etc/rc5.d/S97k4-boot; rm /tmp/k4-boot
      echo 'boot hook installed'
    fi
    if [ -f /tmp/k4-hosts-block ]; then
      [ -f /etc/hosts.k4-orig ] || cp /etc/hosts /etc/hosts.k4-orig
      sed '/^# >>> kindle4ever amazon-block/,/^# <<< kindle4ever amazon-block/d' /etc/hosts > /tmp/hosts.new
      cat /tmp/k4-hosts-block >> /tmp/hosts.new
      cp /tmp/hosts.new /etc/hosts; rm /tmp/hosts.new /tmp/k4-hosts-block
      echo 'amazon block installed'
    fi
    sync"
fi

if [ $START = 1 ]; then
  echo "== starting boot.sh"
  # busybox ps only shows "sh" for scripts, so boot.sh records its pid
  $K sh "[ -f /var/run/k4-boot.pid ] && kill \$(cat /var/run/k4-boot.pid) 2>/dev/null
    cp $D/boot.sh /var/run/k4-boot.sh; cd /
    ( /bin/sh /var/run/k4-boot.sh >> /var/log/k4-boot.log 2>&1 </dev/null & ); echo started"
fi
echo "== done: $($K version)"
