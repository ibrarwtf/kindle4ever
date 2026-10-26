#!/bin/sh
# Download the third-party Kindle 4 packages the setup uses (not redistributed here) and check
# their sha256 against the copies this devkit was tested with. Both are by NiLuJe, from MobileRead.
#   tools/fetch-vendor.sh        -> $K4_VENDOR (default: vendor/), unpacked into jb/ and usbnet/
set -e
. "$(dirname "$0")/lib/env.sh"
V=$K4_VENDOR
mkdir -p "$V/dl"

get() {  # get <name> <attachment id> <sha256> <unpack dir>
  f="$V/dl/$1"
  [ -f "$f" ] || { echo "downloading $1"; curl -sSfL -A "Mozilla/5.0" -o "$f" "https://www.mobileread.com/forums/attachment.php?attachmentid=$2"; }
  echo "$3  $f" | sha256sum -c - || { echo "checksum mismatch for $1 - delete it and retry, or check the MobileRead thread" >&2; exit 1; }
  rm -rf "${V:?}/${4:?}"; mkdir -p "$V/$4"; unzip -q "$f" -d "$V/$4"
}

# JailBreak 1.8.N for K4 - https://www.mobileread.com/forums/showthread.php?t=191158
get kindle-k4-jailbreak-1.8.N.zip 141180 e83da520a25b0186433f50d93e80af7245fbdf2bc2fb3593e25c2c01ddec9c52 jb
# USBNetwork 0.57.N for K4 - https://www.mobileread.com/forums/showthread.php?t=88004
get kindle-usbnetwork-0.57.N-k4.zip 141341 17e22860b623c39aba876078ddeb538d8b09f60b53554e98e9ea5d1ad1291e49 usbnet
# DejaVu fonts (free, Bitstream Vera licence): DejaVu Sans Mono has the box-drawing glyphs the livestation app draws with
if [ ! -f "$V/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSansMono.ttf" ]; then
  echo "downloading DejaVu fonts"
  mkdir -p "$V/dejavu"
  curl -sSfL -o "$V/dejavu/dejavu.zip" "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
  (cd "$V/dejavu" && unzip -qo dejavu.zip && rm -f dejavu.zip)
fi
echo "vendor packages ready in $V"
