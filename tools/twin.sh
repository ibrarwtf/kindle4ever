#!/bin/sh
# Device twin: run kindle4ever scripts and apps on a Linux box (WSL or a Raspberry Pi) with the Kindle's paths in place,
# the simulated screen (tools/sim) and simulated buttons (tools/simweb.py). Two levels of fidelity:
#   tools/twin.sh setup [FONTDIR]     host mode: /mnt/us/kindle4ever -> this checkout's staging dir, stubs for lipc/powerd,
#                                     /etc/TZ, device fonts from FONTDIR (your own copy of /usr/java/lib/fonts) if given.
#   tools/twin.sh run <script> [args] run a device script (k4home, an app.sh) against the simulated screen; needs root.
#   tools/twin.sh arm-setup <img>     exact mode: unpack the Kindle rootfs (partition 1 of a `dd` backup, see docs/recovery.md)
#                                     and run its real busybox under qemu-arm. The rootfs is Amazon's and yours: never share it.
#   tools/twin.sh arm <cmd...>        run a command inside that rootfs (the Kindle's own sh/awk/sed), /mnt/us mapped like host mode.
#   tools/twin.sh status | reset      list, or kill, twin processes left over from earlier runs (k4home, k4keys, apps, listeners).
# The screen is build/sim/screen.raw either way: watch it with tools/simweb.py (from Windows or here).
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
STAGE=$ROOT/build/twin            # what /mnt/us/kindle4ever points at
SIM=$ROOT/build/sim
ARM=$ROOT/build/twin-rootfs       # the Kindle rootfs for arm mode (private)

need_root() { [ "$(id -u)" = 0 ] || { echo "twin: run as root (sudo, or wsl -u root)" >&2; exit 1; }; }

setup() {
  need_root
  mkdir -p "$STAGE/bin" "$STAGE/apps" "$STAGE/run" "$SIM" /mnt/us /var/run /var/log
  # tools: host-built k4draw/k4fetch (Linux), the device scripts, and the simulator stubs (which shadow the real k4keys/k4app)
  for b in build/host/k4draw build/host/k4fetch; do [ -x "$b" ] && cp "$b" "$STAGE/bin/"; done
  cp device/bin/* "$STAGE/bin/"
  cp tools/simbin/* "$STAGE/bin/"
  chmod +x "$STAGE/bin/"*
  cp device/kindle4ever/boot.sh "$STAGE/boot.sh"
  for a in apps/*/; do n=$(basename "$a"); mkdir -p "$STAGE/apps/$n"; cp -r "$a"* "$STAGE/apps/$n/"; done
  # the DejaVu mono font apps draw with: from K4_VENDOR, else vendor/ next to or inside the checkout (tools/fetch-vendor.sh)
  for v in "${K4_VENDOR:-}" "$ROOT/vendor" "$ROOT/../vendor"; do
    f="$v/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSansMono.ttf"
    [ -n "$v" ] && [ -f "$f" ] && { for a in "$STAGE"/apps/*/; do cp "$f" "$a"; done; echo "mono font: $f"; break; }
  done
  git describe --tags --always 2>/dev/null > "$STAGE/VERSION" || echo twin > "$STAGE/VERSION"
  ln -sfn "$STAGE" /mnt/us/kindle4ever
  [ -f /etc/TZ ] || echo "${TWIN_TZ:-IST-5:30}" > /etc/TZ
  if [ -n "$1" ] && [ -d "$1" ]; then mkdir -p /usr/java/lib; ln -sfn "$1" /usr/java/lib/fonts; echo "device fonts: $1"; fi
  echo "twin ready: /mnt/us/kindle4ever -> $STAGE; screen $SIM/screen.raw; start tools/simweb.py and tools/twin.sh run <script>"
}

run_env() {
  export PATH="$STAGE/bin:$PATH"
  export K4DRAW_FB="$SIM/screen.raw" K4DRAW_TRACE="$SIM/trace.txt" K4_SIM="$SIM"
  export LC_ALL=C   # the Kindle has no locale: byte-wise awk/sed like busybox (gawk in a UTF-8 locale counts characters)
  [ -f /etc/TZ ] && { TZ=$(cat /etc/TZ); export TZ; }
}

run() {
  need_root; run_env
  mkdir -p "$SIM"; : > "$SIM/keys.txt"
  echo "$(date +%H:%M:%S) run $*" >> "$SIM/run.log"
  exec /bin/sh "$@"
}

arm_setup() {
  need_root
  img=$1; [ -f "$img" ] || { echo "twin: backup image not found: $img" >&2; exit 1; }
  QEMU=$(command -v qemu-arm-static || command -v qemu-arm || true)
  [ -n "$QEMU" ] || { echo "installing qemu-user"; apt-get install -y -qq qemu-user >/dev/null 2>&1 || apt-get install -y -qq qemu-user-static >/dev/null; QEMU=$(command -v qemu-arm-static || command -v qemu-arm); }
  [ -n "$QEMU" ] || { echo "twin: no qemu-arm found" >&2; exit 1; }
  mkdir -p "$ARM"
  # partition 1 (rootfs) starts at sector 65536 and is 716800 sectors long (docs/recovery.md)
  if [ ! -f "$ARM/bin/busybox" ]; then
    echo "extracting the rootfs (ext3) with debugfs..."
    command -v debugfs >/dev/null || apt-get install -y -qq e2fsprogs >/dev/null
    dd if="$img" of="$ARM.p1.img" bs=512 skip=65536 count=716800 status=none
    debugfs -R "rdump / $ARM" "$ARM.p1.img" 2>/dev/null
    rm -f "$ARM.p1.img"
  fi
  cp "$QEMU" "$ARM/usr/bin/qemu-arm-static"   # must be a static binary to run inside the ARM rootfs
  mkdir -p "$ARM/mnt/us" "$ARM/var/run" "$ARM/var/log" "$ARM/proc" "$ARM/sys" "$ARM/dev"
  bb=$(chroot "$ARM" /usr/bin/qemu-arm-static /bin/busybox 2>&1 | head -1)
  echo "arm twin ready in $ARM (the Kindle's $bb)"
}

arm() {
  need_root
  [ -x "$ARM/usr/bin/qemu-arm-static" ] || { echo "twin: run arm-setup first" >&2; exit 1; }
  # bind what the scripts need: /mnt/us (host-mode staging), the simulator screen, /proc
  mkdir -p "$ARM/mnt/us/kindle4ever" "$ARM$SIM"
  mountpoint -q "$ARM/mnt/us/kindle4ever" || mount --bind "$STAGE" "$ARM/mnt/us/kindle4ever"
  mountpoint -q "$ARM$SIM" || mount --bind "$SIM" "$ARM$SIM"
  mountpoint -q "$ARM/proc" || mount -t proc proc "$ARM/proc"
  # host-built x86 k4draw can't run inside the ARM rootfs: put the ARM builds first on PATH, inside the rootfs (not in the shared stage)
  mkdir -p "$ARM/usr/local/k4"; cp build/k4draw build/k4fetch "$ARM/usr/local/k4/" 2>/dev/null || true
  chroot "$ARM" /usr/bin/qemu-arm-static /bin/busybox sh -c "export PATH=/usr/local/k4:/mnt/us/kindle4ever/bin:/usr/sbin:/sbin:/usr/bin:/bin K4DRAW_FB=$SIM/screen.raw K4DRAW_TRACE=$SIM/trace.txt K4_SIM=$SIM TZ=\$(cat /etc/TZ 2>/dev/null || echo UTC); $*"
}

status() { ps -eo pid,etime,args | grep -e '/var/run/k4home' -e 'bin/k4keys' -e 'lipc-wait-event' -e 'apps/.*/app.sh' | grep -v grep || echo "no twin processes"; }
reset() {
  for p in $(ps -eo pid,args | grep -e '/var/run/k4home' -e 'bin/k4keys' -e 'lipc-wait-event' -e 'apps/.*/app.sh' | grep -v grep | awk '{print $1}'); do kill "$p" 2>/dev/null; done
  rm -f "$SIM/keys.txt" "$SIM/events.txt" "$SIM/events.seen" /var/run/k4home.pid /var/run/k4home.app; : > "$SIM/keys.txt"
  echo "twin processes stopped, key and event queues cleared"
}

case "$1" in
  status) status ;;
  reset) reset ;;
  setup) shift; setup "$@" ;;
  run) shift; run "$@" ;;
  arm-setup) shift; arm_setup "$@" ;;
  arm) shift; arm "$@" ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
