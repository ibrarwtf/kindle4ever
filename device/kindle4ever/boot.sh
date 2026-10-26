#!/bin/sh
# Runs in the background at every boot (from /etc/init.d/k4-boot, after the framework starts).
export PATH=/mnt/us/kindle4ever/bin:/usr/sbin:/sbin:/usr/bin:/bin:/mnt/us/usbnet/bin
if [ -f /etc/TZ ]; then TZ=$(cat /etc/TZ); export TZ; fi   # set by tools/install.sh --tz; busybox ignores /etc/TZ itself
echo $$ > /var/run/k4-boot.pid  # lets tools/install.sh --start replace a running copy
echo "== boot $(date) up=$(cut -d' ' -f1 /proc/uptime)"

# Wait for powerd to answer on lipc (max ~3 min).
i=0
until lipc-get-prop com.lab126.powerd state >/dev/null 2>&1; do
  i=$((i+1)); [ $i -gt 90 ] && { echo "powerd never came up"; exit 1; }
  sleep 2
done

# Don't use preventScreenSaver: with it set, powerd ignores the power button
# ("Prevent screen saver set. Ignoring power button"). Make sure it's off.
lipc-set-prop com.lab126.powerd preventScreenSaver 0

# Clock: Amazon's NTP (ntp-g7g / kindle-time) is blocked in /etc/hosts, so sync from the public pool
# (install.sh --amazon-off also points the stock /usr/sbin/updatetime there). Wi-Fi may still be connecting, so retry for ~2 min.
for _ in 1 2 3 4 5 6 7 8; do
  if ntpdate -u -t 10 pool.ntp.org; then
    hwclock -u -w
    lipc-send-event com.lab126.time timeChanged >/dev/null 2>&1
    echo "time synced: $(date -u)"
    break
  fi
  sleep 15
done

# Home screen instead of Amazon's UI (install.sh --home creates the flag; Amazon's own framework script honours it).
if [ -f /mnt/us/DONT_START_FRAMEWORK ] && [ -x /mnt/us/kindle4ever/bin/k4home ]; then
  ( /mnt/us/kindle4ever/bin/k4home >> /var/log/k4-home.log 2>&1 </dev/null & )   # it re-execs itself from /var/run
  echo "k4home started"
fi

# Keep-awake: reset the 10-min idle timer every 2 min while the device is active, so it never
# auto-sleeps but the power button still locks it. In screensaver the property is rejected,
# so this never wakes a device the user put to sleep.
echo "keep-awake loop started up=$(cut -d' ' -f1 /proc/uptime)"
while :; do
  [ "$(lipc-get-prop com.lab126.powerd state 2>/dev/null)" = "active" ] &&
    lipc-set-prop com.lab126.powerd touchScreenSaverTimeout 1 >/dev/null 2>&1
  sleep 120
done
