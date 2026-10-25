#!/bin/sh
# Copy files onto the Kindle's USB drive for each setup step (see docs/setup.md).
#   tools/stage-usb.sh <drive> jailbreak       jailbreak files + our read-only info dump (runme.sh)
#   tools/stage-usb.sh <drive> usbnet-install  the USBNetwork installer .bin
#   tools/stage-usb.sh <drive> usbnet-config   after USBNetwork is installed: Wi-Fi SSH config,
#                                              your public key, start at boot
# <drive> is where the Kindle is mounted: /d or D: (Git Bash), /media/$USER/Kindle, /Volumes/Kindle.
# Needs: tools/fetch-vendor.sh first; usbnet-config needs K4_SSH_KEY (its .pub is installed).
set -e
. "$(dirname "$0")/lib/env.sh"
cd "$K4_ROOT"
[ $# -eq 2 ] || { sed -n '2,9p' "$0"; exit 2; }
drive=$(printf '%s' "$1" | sed -E 's#^([A-Za-z]):/?$#/\L\1#')  # D: -> /d
[ -d "$drive/documents" ] || { echo "$drive doesn't look like the Kindle drive (no documents/)" >&2; exit 1; }
V=$K4_VENDOR

case "$2" in
  jailbreak)
    [ -f "$V/jb/data.tar.gz" ] || { echo "run tools/fetch-vendor.sh first" >&2; exit 1; }
    cp "$V/jb/data.tar.gz" "$V/jb/ENABLE_DIAGS" "$drive/"
    cp -r "$V/jb/diagnostic_logs" "$drive/"
    [ -f "$V/jb/diagnostic_logs/device_info.xml" ] || echo "warning: diagnostic_logs/device_info.xml missing - the jailbreak may fail" >&2
    tr -d '\r' < device/jailbreak/runme.sh > "$drive/runme.sh"
    echo "staged jailbreak. Next: eject, unplug, Menu > Settings > Menu > Restart, then in diags: D) Exit... > R) Reboot > Q"
    ;;
  usbnet-install)
    bin=$(ls "$V"/usbnet/Update_usbnetwork_*_k4_install.bin 2>/dev/null | head -1)
    [ -n "$bin" ] || { echo "run tools/fetch-vendor.sh first" >&2; exit 1; }
    cp "$bin" "$drive/"
    echo "staged $(basename "$bin"). Next: eject, unplug, Menu > Settings > Menu > Update Your Kindle"
    ;;
  usbnet-config)
    k4_need K4_SSH_KEY
    [ -f "$K4_SSH_KEY.pub" ] || { echo "missing $K4_SSH_KEY.pub (ssh-keygen -t rsa -b 2048 -f \"$K4_SSH_KEY\")" >&2; exit 1; }
    [ -d "$drive/usbnet/etc" ] || { echo "no usbnet/ on the drive - install USBNetwork first (usbnet-install)" >&2; exit 1; }
    tr -d '\r' < device/usbnet/config > "$drive/usbnet/etc/config"
    tr -d '\r' < "$K4_SSH_KEY.pub" > "$drive/usbnet/etc/authorized_keys"
    [ -f "$drive/usbnet/DISABLED_auto" ] && mv "$drive/usbnet/DISABLED_auto" "$drive/usbnet/auto"
    : > "$drive/usbnet/verbose"
    echo "staged USBNetwork config (Wi-Fi SSH, key auth, start at boot). Next: eject, unplug, restart, join Wi-Fi,"
    echo "then: tools/find-kindle.ps1 (Windows) or tools/find-kindle.sh, and tools/install.sh"
    ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
sync
