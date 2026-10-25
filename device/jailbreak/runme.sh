#!/bin/sh
# Runs as root at the end of the K4 jailbreak (likely from diags). Read-only info dump to /mnt/us/devinfo.
OUT=/mnt/us/devinfo
mkdir -p "$OUT"
run() { name="$1"; shift; { echo "\$ $*"; "$@"; } > "$OUT/$name.txt" 2>&1; }
run uname uname -a
run version cat /etc/version.txt /etc/prettyversion.txt
run bootmode idme --bootmode ?
run usid cat /proc/usid
run cpuinfo cat /proc/cpuinfo
run meminfo cat /proc/meminfo
run cmdline cat /proc/cmdline
run partitions cat /proc/partitions
run mounts cat /proc/mounts
run df df -k
run input cat /proc/bus/input/devices
run devinput ls -la /dev/input
run fb sh -c 'for f in /sys/class/graphics/fb0/*; do [ -f "$f" ] && echo "$f: $(cat $f 2>/dev/null)"; done'
run uks ls -la /etc/uks
run ps ps
run busybox busybox
run bins sh -c 'ls /bin /sbin /usr/bin /usr/sbin'
run modules sh -c 'cat /proc/modules; ls -R /lib/modules'
run initd ls -la /etc/init.d /etc/rc5.d
run dmesg dmesg
run net sh -c 'ifconfig -a; cat /proc/net/wireless'
sync
