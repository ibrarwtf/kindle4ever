# Changelog

User-facing notes per release. The release workflow publishes the section matching the tag.

## v1.4.0

- **Deep sleep by default.** `install.sh --sleep` sets powerd to screensaver after 3 min idle and suspend right after, the same
  path the power button takes. boot.sh no longer keeps the device awake unless `/mnt/us/kindle4ever/KEEP_AWAKE` exists.
  k4home shows one screensaver image on the way to sleep (random from `/mnt/us/kindle4ever/screensavers/*.png`, else Amazon's
  stock set) and redraws on wake; `/mnt/us/kindle4ever/WAKE_EVERY`
  (seconds) arms powerd's RTC alarm at `readyToSuspend` for scheduled wakes, absent by default so only the power button wakes it.
- `tools/k4 hold` / `wait`, `tools/twin.sh status` / `reset`, `tools/release.sh`: the small tools the day's work kept needing.
- **k4draw `-a` auto refresh**: snapshots the screen at start, diffs at the end, refreshes only the changed box partially, and
  flashes when the box covers 60% of the screen, 30% of pixels changed, or after 10 partials (ghosting). Live station uses it,
  so a 5-minute refresh that only moves a few times no longer flashes the whole panel.

## v1.3.0

- **Simulator, second stage.** `tools/sim serve` opens a local page with the simulated screen, the 13 buttons and keyboard
  shortcuts; `tools/twin.sh` runs device scripts and apps unmodified on Linux/WSL against that screen (host mode), or inside the
  Kindle's own root filesystem under qemu-arm (`arm` mode, from your backup image: the Kindle's real busybox, awk and sh).
  Simulated `k4keys`, `lipc-*`, `gasgauge-info`, `k4app` and `powerd_test` live in `tools/simbin/`.
- k4draw: `K4DRAW_TRACE` records every refresh in sim mode (the viewer outlines partial regions and counts flashes);
  `K4DRAW_FONTDIR` maps the device font folder to a local copy, so text measures as on the panel.
- livestation: `LIVESTATION_FIXTURE=page.html` runs the whole pipeline offline.
- CI: `tools/ci-sim.sh` parses every device script and awk program with busybox, draws k4home under busybox sh with the stubs,
  runs the livestation pipeline on the fixture in landscape, and checks that the ARM k4draw (under qemu) renders pixel-identical
  to the host build. No private files involved; the same script runs locally in WSL.

## v1.2.0

- **k4draw landscape mode**: `K4DRAW_ROTATE=90` (device turned anticlockwise, keypad on the right) or `270`. Commands, the
  dirty-rectangle refresh and `export` all work in 800x600 landscape coordinates; k4draw rotates into the portrait framebuffer.
- **Apps on the home screen**: `k4home` lists every `/mnt/us/kindle4ever/apps/<name>/app.sh` (label from its `# name:` line)
  as a cell after Reader and About, wrapping two per row. An app runs with the screen already taken and returns on Back/Home.
- **`apps/livestation`**: the first app. An Indian Railways live platform board for one station (NTES), drawn as trains,
  fully on the device: `k4fetch` + three busybox awk programs + `k4draw` landscape. About 1.2 s CPU and under 1.5 MB per refresh.
  Configured by one small `station.conf` (your station, its neighbours); `tools/k4 app apps/livestation` installs it.
- Apps can ship an `icon.sh` that prints k4draw commands for their home-screen icon; `tools/fetch-vendor.sh` now also fetches
  the DejaVu fonts (DejaVu Sans Mono has the box-drawing glyphs the board uses).
- Apps carry their own `# version:` line (livestation 0.1.0); the kindle4ever tag versions the bundle that ships them.
- Private apps and configs stay out of this repo; only the folder convention is public.

## v1.1.0

- **`install.sh --amazon-off`**: stops and disables Amazon's phone-home (`phd`) and transfer (`tmd`) daemons. `phd` retried Amazon
  every 30-60 min and asked powerd for an RTC wakeup before each suspend, so a sleeping Kindle woke up to phone home. Also points the
  stock clock sync (`/usr/sbin/updatetime`) at `pool.ntp.org`. New doc: `docs/amazon.md`, one place for everything Amazon-related.
- **`install.sh --no-browser`**: stops and disables the experimental web browser (`webreader`, `browserd`, about 21 MB of RAM).
- **`install.sh --tz <zone>`**: time zone for the device (zoneinfo file, `/etc/TZ`, and `TZ` exported by `boot.sh`, `tools/k4` and login shells,
  because the stock busybox ignores the files). `tools/lib/tzfile.py` builds the zone file from your computer's tzdata or a fixed offset.
- **`k4home`** and **`install.sh --home`**: a minimal home screen that replaces Amazon's UI at boot (Amazon's own `DONT_START_FRAMEWORK` flag):
  status bar (clock, cpu %, ram %, Wi-Fi, battery), two items, Reader (starts Amazon's UI with the right time zone for Java) and About.
  5-way to choose (only the two cells' border strips are redrawn and partially refreshed), Select to open (full flash on every screen
  change), hold the Keyboard key in the Reader to come back. `k4about` clears the screen and returns to whoever called it.
  `k4app off` lifts the home flag while Amazon's UI starts. Frees about 50 MB of RAM and the Java UI's CPU time.
- **`k4logs`**: log sizes, `clean [DAYS]` for old archives in `/var/local/log`, `tail` without lipc chatter.
- `uninstall.sh` reverses all of the above (rc5.d links, ntp, TZ, profile, home flag).
- Findings: phd/RTC behaviour, powerd's `rtcWakeup` property, log history (starts 2025, not 2012), time zone handling.

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
