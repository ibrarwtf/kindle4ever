# Find zig (sourced): $K4_ZIG, else toolchain/zig (tools/setup-toolchain.sh), else zig on PATH. Sets ZIG.
_zroot=${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
ZIG=${K4_ZIG:-}
if [ -z "$ZIG" ]; then
  for z in "$_zroot/toolchain/zig/zig.exe" "$_zroot/toolchain/zig/zig"; do [ -x "$z" ] && { ZIG=$z; break; }; done
fi
[ -n "$ZIG" ] || ZIG=$(command -v zig) || { echo "zig not found, run tools/setup-toolchain.sh" >&2; exit 1; }
