#!/bin/sh
# Download the pinned Zig compiler into toolchain/zig (used by tools/kcc), checking its sha256
# against ziglang.org's release index.
#   tools/setup-toolchain.sh
set -e
ZIG_VERSION=0.14.1
cd "$(dirname "$0")/.."
PY=${PYTHON:-$(command -v python3 || command -v python)}

case "$(uname -s)" in
  Linux) os=linux ;; Darwin) os=macos ;; MINGW*|MSYS*|CYGWIN*) os=windows ;; *) echo "unsupported OS" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=aarch64 ;; *) echo "unsupported CPU" >&2; exit 1 ;;
esac
key="$arch-$os"

zigbin() { for z in toolchain/zig/zig.exe toolchain/zig/zig; do [ -x "$z" ] && { echo "$z"; return 0; }; done; return 1; }
if z=$(zigbin); then
  echo "toolchain/zig already present ($("$z" version))"; exit 0
fi

mkdir -p toolchain/dl
curl -sSfL -o toolchain/dl/index.json https://ziglang.org/download/index.json
read -r url sum <<EOF
$("$PY" -I -c "import json;e=json.load(open('toolchain/dl/index.json'))['$ZIG_VERSION']['$key'];print(e['tarball'],e['shasum'])")
EOF
file=toolchain/dl/$(basename "$url")
echo "downloading $url"
curl -sSfL -o "$file" "$url"
echo "$sum  $file" | sha256sum -c -
case "$file" in
  *.zip) unzip -q "$file" -d toolchain ;;
  *) tar -xf "$file" -C toolchain ;;
esac
rm -rf toolchain/zig
mv "toolchain/$(basename "$file" | sed -E 's/\.(zip|tar\.xz)$//')" toolchain/zig
z=$(zigbin) && echo "zig $("$z" version) ready in toolchain/zig"
