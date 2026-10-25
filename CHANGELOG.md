# Changelog

User-facing notes per release. The release workflow publishes the section matching the tag.

## v1.0.0

First public release: a jailbroken Kindle 4 NT (firmware 4.1.4) you, or an AI coding agent, can program over Wi-Fi.

- **Setup scripts:**
  - `stage-usb.sh` stages the jailbreak and USBNetwork (SSH over Wi-Fi, key auth) on the USB drive.
  - `install.sh` / `uninstall.sh` install kindle4ever over SSH: tools, a boot hook with a kill switch, and an optional Amazon-services block.
  - `find-kindle` ejects the drive (which is what turns Wi-Fi off) and finds the device by MAC.
- **Device tools:**
  - `k4draw`: e-ink drawing. TrueType text (left-aligned or centred), shapes, PNG/JPEG, partial or full refresh, PNG export.
  - `k4keys`: read all 13 buttons.
  - `k4fetch`: HTTPS with its own TLS 1.2.
  - `k4app`: take the screen from Amazon's UI and give it back.
  - `k4press`, `k4wait`: inject keys, wait for the screen to settle.
  - `k4doctor`: self-test.
  - `k4welcome`, `k4about`, `k4logo`: welcome screen, neofetch-style card, and the logo, drawn from rectangles so the device, README and SVG match.
  - Every tool has `--help`; together they form the contract in `docs/tools.md`.
- **From your computer:**
  - `tools/k4`: `sh`, `shot`, `press`, `push`, `run`, `deploy`, `version`. It warns when the device runs a different kindle4ever version.
  - `tools/doctor.sh`: a sanitized compatibility report.
  - `tools/sim`: render exactly what the panel would show, without a device.
- **Docs:** setup, verified hardware facts, findings (online claims checked on the device), recovery, research, and how it was built.
- **CI:** line endings, ShellCheck, leak checks (generic patterns plus gitleaks over the whole history), build, and the ARM binaries run under qemu, including a real HTTPS fetch.
