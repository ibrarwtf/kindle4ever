#!/bin/sh
# Regenerate docs/tools.md from each device tool's --help (the tools' stable contract).
#   tools/gen-tools-doc.sh            run the ARM binaries with qemu-arm if available, else on the Kindle (tools/k4)
#   tools/gen-tools-doc.sh --check    exit 1 if docs/tools.md is out of date (CI)
# Build first: tools/build.sh
set -e
cd "$(dirname "$0")/.."
out=docs/tools.md
tmp=$(mktemp)

if command -v qemu-arm >/dev/null 2>&1 || command -v qemu-arm-static >/dev/null 2>&1; then
  q=$(command -v qemu-arm || command -v qemu-arm-static)
  help_bin() { "$q" "build/$1" --help; }
else
  help_bin() { tools/k4 sh "$1 --help"; }
fi
help_sh() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "device/bin/$1"; }

{
  echo "# Device tools"
  echo
  echo "The command-line contract of the tools installed in \`/mnt/us/kindle4ever/bin\`: options, output and exit codes."
  echo "Apps and scripts may rely on these. Changing them is a breaking change, noted in CHANGELOG.md."
  echo "Generated from each tool's \`--help\` by \`tools/gen-tools-doc.sh\` (CI checks it's current)."
  for t in k4draw k4keys k4fetch; do
    printf '\n## %s\n\n```\n' "$t"; help_bin "$t" | tr -d '\r'; printf '```\n'
  done
  for t in k4press k4wait k4app k4about k4welcome k4logo; do
    printf '\n## %s\n\n```\n' "$t"; help_sh "$t"; printf '```\n'
  done
} > "$tmp"

if [ "$1" = "--check" ]; then
  if cmp -s "$tmp" "$out"; then echo "$out is current"; rm -f "$tmp"; exit 0; fi
  echo "$out is out of date - run tools/gen-tools-doc.sh" >&2; diff "$out" "$tmp" >&2 || true; rm -f "$tmp"; exit 1
fi
mv "$tmp" "$out"; echo "wrote $out"
