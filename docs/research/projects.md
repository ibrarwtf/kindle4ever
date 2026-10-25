# Research: K4NT projects, patterns, do's and don'ts (2026-10-25)

> Research notes from before kindle4ever was built (web sources, with links). What was later verified on a device is in [../hardware.md](../hardware.md) and [../findings.md](../findings.md).

Web research only. Key sources are inline.

## Critical context (Oct 2026)
- **Amazon ended K4 support on 2026-05-20.** A deregistered or factory-reset K4 reportedly can't be re-registered. **Never factory reset.**
  - https://techcrunch.com/2026/04/08/amazon-to-end-support-for-older-kindle-devices-2012/
- **4.1.4 is the last K4 firmware**, so OTA risk is low. Blocking OTA still costs nothing (rename /etc/uks; rename it back before installing a .bin).
- Amazon strips `/var/local/java/keystore/developer.keystore` when the device reaches its servers, and KUAL/Kindlets then break.
  The old KUAL/MKK keys also expired in April 2025. **We don't use KUAL/Kindlets**, so native + init.d avoids all of this.
  - https://www.mobileread.com/forums/showthread.php?p=4530646

## Verified on a device (main boot, 2026-10-25)
- fb0 `eink_fb`, line_length **600**, 600x800, yoffset 0, rotate 0, grayscale. `/proc/eink_fb/update_display` exists.
  (The 608 stride / 4480 virtual / mxc_epdc_fb values came from **diags** and don't apply to normal use.)
- /etc/uks: pubdevkey01 (jailbreak) + 2 prod keys. RTCs: rtc0, rtc1. Cron dir: /etc/crontab/root.

## Projects (how they work)
- **kindle-dash** (MIT, K4NT): server renders a PNG → `eips -g` (`-f` every 4). Stops framework + webreader, preventScreenSaver, RTC wake + `echo mem > /sys/power/state`. About 30 days per charge. Ships its own HTTPS client (stock TLS too old). https://github.com/pascalw/kindle-dash
- **Petroff weather** (2012): server SVG → gray PNG, cron, `eips -c` x2, then `eips -g`. Stops framework + powerd.
- **x-magic weather stand-alone**: renders on the device (python + rsvg). Wi-Fi on/off via `lipc-set-prop com.lab126.cmd wirelessEnable`, `rtc1/wakealarm`, suspend. About 4 weeks hourly.
- **hass-lovelace-kindle-4**: Home Assistant screenshot server, plain HTTP, rtcwake, pid lock, timeouts.
- **Life-Dashboard**: FBInk instead of eips.
- **KOReader**: own fb (einkfb) + input stack. Launched via KUAL (fragile now).
- Not relevant / not viable: kterm (touch-only), Kindlets (keystore issues), kite (boot loops), Debian chroot (Squeeze-era, heavy).

## Patterns
- Dedicated-display apps **stop the framework** (`/etc/init.d/framework stop`), often powerd too. Running alongside the framework = fighting its redraws.
- **Always include a kill switch** and a delayed start in boot hooks (boot loops are the classic K4 failure).
- Input: read /dev/input/event0/1 directly. event0 sends an extra code-4 "begin" event before each key.
- Networking: stock curl/wget can't do modern TLS. Use plain HTTP on the LAN, or bring our own TLS client.
- Display refresh dominates battery use.

## Do / don't
- Do: keep backups off-device (done). `mntroot ro` after edits. Fail-safe boot hooks (done: DISABLE_BOOT, runs from tmpfs).
  Charge for a long time before diagnosing a "brick". Use only K4-specific .bin files. Time-box Wi-Fi waits.
- Don't: factory reset/deregister. Fill /var/local. Run critical things from /mnt/us (it vanishes during USB mounts; we hit this).
  Run fastboot/diags commands blindly. Boot with custom .bins on the drive root.
- Recovery extra: USB downloader mode = hold power until the LED goes off, hold 5-way Down, release power, then release Down, then MfgTool/Kubrick (re-flashes 4.1.1).
  https://www.mobileread.com/forums/showthread.php?p=1972279 . Serial pads P2: GND, RxD, TxD.

## Battery (old cells, expect less)
- Suspend between updates: about 30 days. Awake with services off: about 2 weeks. Framework + Wi-Fi always on: a few days.
