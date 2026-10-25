#!/bin/sh
# Self-test the Kindle and print a compatibility report you can paste into a GitHub issue.
#   tools/doctor.sh              plain report
#   tools/doctor.sh --markdown   markdown table
# Checks: system, devkit version and binaries, boot hook, display (memory-only draw test,
# screen untouched), key injection round trip, Wi-Fi + HTTPS, power, free space.
# No personal data is printed (no serial, MAC, IP or Wi-Fi name). Exit 1 if any check FAILs.
# Risk: read-only, apart from a few framebuffer bytes it restores and one key on an unused input device.
. "$(dirname "$0")/lib/env.sh"
cd "$K4_ROOT" || exit 1
MD=0; [ "$1" = "--markdown" ] && MD=1
. "$(dirname "$0")/lib/version.sh"; HOSTVER=$(k4_version)

out=$(mktemp)
if ! tools/k4 sh 'true' 2>/dev/null; then
  echo "FAIL|ssh|can't reach the Kindle at ${K4_HOST:-?} (asleep? drive mounted? run tools/find-kindle)" > "$out"
else
  # push the on-device half so the check matches this checkout, then run it in one SSH round trip
  tools/k4 push device/bin/k4doctor /tmp/k4doctor
  tools/k4 sh "sh /tmp/k4doctor '$HOSTVER'; rm -f /tmp/k4doctor" > "$out" 2>&1
  sed -i '1i PASS|ssh|reachable' "$out"
fi

fails=$(grep -c '^FAIL|' "$out")
warns=$(grep -c '^WARN|' "$out")
if [ $MD = 1 ]; then
  echo "**kindle4ever doctor** (host $HOSTVER)"
  echo
  echo "| | check | detail |"
  echo "|---|---|---|"
  grep '|' "$out" | sed 's/|/ | /g; s/^/| /; s/$/ |/'
  echo
  echo "$fails failed, $warns warnings"
else
  echo "kindle4ever doctor (host $HOSTVER)"
  grep '|' "$out" | awk -F'|' '{ printf "%-5s %-15s %s\n", $1, $2, $3 }'
  echo "$fails failed, $warns warnings"
fi
rm -f "$out"
[ "$fails" -eq 0 ]
