#!/bin/sh
# Build every device binary into build/.
#   tools/build.sh                  build k4draw, k4keys, k4fetch, examples
#   tools/build.sh --update-roots   first refresh k4fetch's root CAs (src/k4fetch/roots.txt) from the
#                                   current Mozilla bundle (curl.se, sha256-checked)
# The version stamped into each binary comes from git describe (or VERSION in a release tarball).
set -e
cd "$(dirname "$0")/.."
KCC=tools/kcc
PY=${PYTHON:-$(command -v python3 || command -v python)}
. tools/lib/version.sh
VERSION=$(k4_version)
DEF="-DK4_VERSION=\"$VERSION\""

if [ "$1" = "--update-roots" ]; then
  tmp=$(mktemp -d)
  echo "fetching Mozilla CA bundle"
  curl -sSfL -o "$tmp/cacert.pem" https://curl.se/ca/cacert.pem
  curl -sSfL -o "$tmp/cacert.pem.sha256" https://curl.se/ca/cacert.pem.sha256
  (cd "$tmp" && sha256sum -c cacert.pem.sha256)
  "$PY" -I src/k4fetch/gen_roots.py extract "$tmp/cacert.pem" src/k4fetch/roots.txt src/k4fetch/roots
  rm -rf "$tmp"
fi

mkdir -p build/gen
echo "version $VERSION"

echo "k4draw";  $KCC -Wall "$DEF" -o build/k4draw src/k4draw/k4draw.c -lm
echo "k4keys";  $KCC -Wall "$DEF" -o build/k4keys src/k4keys/k4keys.c
echo "k4fetch"
"$PY" -I src/k4fetch/gen_roots.py anchors src/k4fetch/roots build/gen/k4fetch_tas.c
# shellcheck disable=SC2046  # word splitting of the file list is intended
$KCC -Wall "$DEF" -I third_party/bearssl/inc -I third_party/bearssl/src \
  -o build/k4fetch src/k4fetch/k4fetch.c build/gen/k4fetch_tas.c \
  $(find third_party/bearssl/src -name '*.c' | sort)
echo "hello (example)"; $KCC -Wall -o build/hello examples/hello.c

# k4draw for this computer too: the simulator (K4DRAW_FB=file, see tools/sim)
ROOT=$(pwd); export ROOT; . tools/lib/zig.sh
mkdir -p build/host
# Explicit host target: under WSL the zig found may be the Windows one, which would otherwise build a Windows .exe
ext=; target=
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ext=.exe; target="-target x86_64-windows-gnu" ;;
  Linux) target="-target $(uname -m)-linux-gnu" ;;
  Darwin) target="-target $(uname -m | sed s/arm64/aarch64/)-macos" ;;
esac
# shellcheck disable=SC2086  # $target is two words on purpose
echo "k4draw (host simulator)"; "$ZIG" cc -O2 -s -Wall "$DEF" $target -o "build/host/k4draw$ext" src/k4draw/k4draw.c -lm
# k4fetch for this computer: the twin (tools/twin.sh) runs apps that fetch; Windows builds skip it (no POSIX sockets)
if [ -z "$ext" ]; then
  echo "k4fetch (host)"
  # shellcheck disable=SC2046,SC2086  # word splitting of the file list and of $target is intended
  "$ZIG" cc -O2 -s -Wall "$DEF" $target -I third_party/bearssl/inc -I third_party/bearssl/src     -o build/host/k4fetch src/k4fetch/k4fetch.c build/gen/k4fetch_tas.c $(find third_party/bearssl/src -name '*.c' | sort)
fi
rm -f build/host/*.pdb

ls -l build/k4draw build/k4keys build/k4fetch build/hello
