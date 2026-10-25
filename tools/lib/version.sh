# Devkit version (sourced): git describe in a checkout, else the VERSION file of a release tarball, else "dev".
k4_version() {
  _vroot=$(cd "$(dirname "$0")/.." && pwd)
  git -C "$_vroot" describe --tags --always --dirty 2>/dev/null ||
    { [ -f "$_vroot/VERSION" ] && tr -d '\r\n' < "$_vroot/VERSION"; } || echo dev
}
