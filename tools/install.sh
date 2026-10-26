#!/bin/sh
# Install (or update) the devkit on a jailbroken Kindle 4 NT that has USBNetwork SSH working.
#   tools/install.sh [--amazon-block] [--amazon-off] [--no-browser] [--tz ZONE] [--home] [--sleep] [--no-boot-hook] [--start]
#     --amazon-block   add the Amazon-services block to /etc/hosts (device/rootfs/etc/hosts.amazon-block)
#     --amazon-off     stop and disable Amazon's phone-home (phd) and transfer (tmd) daemons,
#                      and point the stock clock sync at pool.ntp.org instead of Amazon (docs/amazon.md)
#     --no-browser     stop and disable the experimental web browser (webreader, browserd): frees ~21 MB RAM
#     --tz ZONE        set the time zone (Asia/Kolkata, Europe/Berlin, or a fixed offset like IST-5:30); the stock system is UTC
#     --home           boot into kindle4ever's home screen (k4home) instead of Amazon's UI; the Reader item starts Amazon's UI
#     --sleep          deep sleep: screensaver after 3 min idle or the power button, suspend right after (powerd's own grace
#                      of ~45 s applies); #                      timers in kdb (originals saved to /etc/kdb.k4-orig), takes effect at the next boot or powerd restart
#     --no-boot-hook   don't install /etc/init.d/k4-boot (boot.sh won't run at boot)
#     --start          (re)start boot.sh now instead of waiting for the next reboot
# Safe to run again: it updates files in place. Build first: tools/build.sh
#
# Writes to the Kindle:
#   /mnt/us/kindle4ever/{bin,run}, boot.sh, VERSION        userstore (FAT), no root fs changes
#   /etc/init.d/k4-boot, /etc/rc5.d/S97k4-boot  root fs, via mntroot rw/ro (unless --no-boot-hook)
#   /etc/hosts (+ backup /etc/hosts.k4-orig)       only with --amazon-block
#   /etc/rc5.d/S75phd S90tmd removed (list kept in /etc/rc5.d/.k4-disabled), /etc/sysconfig/ntp (+ .k4-orig)   --amazon-off
#   /etc/rc5.d/S93webreaderd S94browserd removed (same list)                                                   --no-browser
#   /var/local/system/tz (zoneinfo), /etc/TZ (+ .k4-orig), one TZ line in /etc/profile (+ .k4-orig)             --tz
#   /mnt/us/DONT_START_FRAMEWORK (Amazon's own flag; userstore, no root fs change)                             --home
set -e
. "$(dirname "$0")/lib/env.sh"
cd "$K4_ROOT"
K=tools/k4
D=$K4_DEVICE_DIR
AMAZON=0 AMAZON_OFF=0 NOBROWSER=0 TZONE="" HOMESCREEN=0 SLEEP=0 HOOK=1 START=0
while [ $# -gt 0 ]; do
  case "$1" in
    --amazon-block) AMAZON=1 ;;
    --amazon-off) AMAZON_OFF=1 ;;
    --no-browser) NOBROWSER=1 ;;
    --tz) shift; TZONE=$1; [ -n "$TZONE" ] || { echo "--tz needs a zone" >&2; exit 2; } ;;
    --home) HOMESCREEN=1 ;;
    --sleep) SLEEP=1 ;;
    --no-boot-hook) HOOK=0 ;;
    --start) START=1 ;;
    *) sed -n '2,19p' "$0"; exit 2 ;;
  esac
  shift
done
PY=${PYTHON:-$(command -v python3 || command -v python)}
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

# rc5.d services to disable: the S link is removed and recorded in /etc/rc5.d/.k4-disabled so uninstall.sh can put it back.
DISABLE=""
[ $AMAZON_OFF = 1 ] && DISABLE="$DISABLE phd tmd"
[ $NOBROWSER = 1 ] && DISABLE="$DISABLE webreader browserd"
POSIX_TZ=""
if [ -n "$TZONE" ]; then
  POSIX_TZ=$("$PY" tools/lib/tzfile.py "$TZONE" build/tz.bin)
  $K pushbin build/tz.bin /tmp/k4-tz; rm -f build/tz.bin
  # Java (Amazon's UI) wants the IANA name, busybox the POSIX string: k4app passes this file as TZ when it starts the UI.
  case "$TZONE" in */*) printf '%s\n' "$TZONE" > build/tz.java ;; *) printf '%s\n' "$POSIX_TZ" > build/tz.java ;; esac
  $K push build/tz.java "$D/tz.java"; rm -f build/tz.java
fi
if [ $HOMESCREEN = 1 ]; then
  $K sh "touch /mnt/us/DONT_START_FRAMEWORK" && echo "home screen at boot: on (k4home replaces Amazon's UI; its Reader item starts it)"
fi

if [ $HOOK = 1 ] || [ $AMAZON = 1 ] || [ -n "$DISABLE" ] || [ -n "$POSIX_TZ" ] || [ $SLEEP = 1 ]; then
  [ $HOOK = 1 ] && $K push device/rootfs/etc/init.d/k4-boot /tmp/k4-boot
  [ $AMAZON = 1 ] && $K push device/rootfs/etc/hosts.amazon-block /tmp/k4-hosts-block
  echo "== root fs (mntroot rw ... ro)"
  $K sh "set -e; mntroot rw >/dev/null
    trap 'mntroot ro >/dev/null' EXIT
    for d in $DISABLE; do
      # stop it now (pmond supervises these daemons), then drop its rc5.d start link
      lipc-set-prop com.lab126.pmond stop \$d >/dev/null 2>&1 || true
      killall \$d >/dev/null 2>&1 || true   # browserd ignores pmond's stop
      for l in /etc/rc5.d/S??\$d /etc/rc5.d/S??\${d}d; do
        [ -L \"\$l\" ] || continue
        grep -qs \"^\$(basename \$l) \" /etc/rc5.d/.k4-disabled || echo \"\$(basename \$l) \$(readlink \$l)\" >> /etc/rc5.d/.k4-disabled
        rm \"\$l\"; echo \"disabled \$(basename \$l)\"
      done
    done
    if [ $AMAZON_OFF = 1 ] && grep -q '^NTP_SERVER=ntp-g7g' /etc/sysconfig/ntp; then
      cp /etc/sysconfig/ntp /etc/sysconfig/ntp.k4-orig
      sed 's/^NTP_SERVER=.*/NTP_SERVER=pool.ntp.org/' /etc/sysconfig/ntp.k4-orig > /etc/sysconfig/ntp
      echo 'clock sync now uses pool.ntp.org'
    fi
    if [ -f /tmp/k4-tz ]; then
      [ -f /etc/TZ.k4-orig ] || cp /etc/TZ /etc/TZ.k4-orig
      cp /tmp/k4-tz /var/local/system/tz; rm /tmp/k4-tz   # /etc/localtime already points here (glibc)
      echo '$POSIX_TZ' > /etc/TZ
      # The stock busybox ignores both files, so interactive shells get TZ from /etc/profile
      # (boot.sh and tools/k4 export it the same way).
      [ -f /etc/profile.k4-orig ] || cp /etc/profile /etc/profile.k4-orig
      grep -q 'k4-tz' /etc/profile || echo '[ -f /etc/TZ ] && export TZ=\$(cat /etc/TZ)  # k4-tz' >> /etc/profile
      echo 'time zone set: $TZONE ($POSIX_TZ)'
    fi
    if [ $SLEEP = 1 ]; then
      [ -f /etc/kdb.k4-orig ] || printf 't1_timeout=%s\nt2_timeout=%s\n' \"\$(kdb get system/daemon/powerd/t1_timeout)\" \"\$(kdb get system/daemon/powerd/t2_timeout)\" > /etc/kdb.k4-orig
      kdb set system/daemon/powerd/t1_timeout 180 && kdb set system/daemon/powerd/t2_timeout 2 && echo 'deep sleep timers set (idle 180 s, suspend right after)'
    fi
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
