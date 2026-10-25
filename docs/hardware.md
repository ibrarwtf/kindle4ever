# Kindle 4 NT: verified device facts

Measured on a Kindle 4 Non-Touch (2012, black, serial prefix `9023`) running firmware **4.1.4**, in normal (main) boot,
unless marked otherwise. The silver 2011 K4 (`B00E`) should match. This is a write-up of what's actually on the device,
not forum lore. See [findings.md](findings.md) for claims we checked.

## System
| | |
|---|---|
| SoC | Freescale i.MX50 ("YOSHI" board), ARMv7 Cortex-A8, 800 MHz, NEON/VFPv3 |
| RAM | 256 MB (about 200 MB free with the UI running) |
| Storage | 2 GB eMMC. p1 rootfs 350 MB (ext3, read-only), p2 diags 64 MB, p3 `/var/local` 32 MB, p4 userstore 1.4 GB (FAT32, `/mnt/us`, the USB drive) |
| Kernel | `2.6.31-rt11-lab126` (2013 build), no IPv6 |
| libc | glibc 2.12.1, so kindle4ever builds fully static musl binaries instead |
| Userland | BusyBox **1.7.2** (no `grep -E`, no `od`, no `nohup`, `sed` treats `\r` as a literal `r`), OpenSSL 0.9.8j, curl 7.21.4 |
| Init | SysV (`/etc/init.d`, `/etc/rc5.d`), no upstart. UI = Java "framework" (`cvm`), `/etc/init.d/framework stop|start` |
| USB | `1949:0004` mass storage. While the drive is mounted on a computer, `/mnt/us` is gone on the device **and Wi-Fi is off** |
| Wi-Fi | `wifid` + `wpa_supplicant`. DNS via `/etc/resolv.conf` → `/var/run/resolv.conf`. `netwatchd` isn't running in rc5 |
| Clock | Amazon NTP by default (`/usr/sbin/updatetime`, `ntp-g7g.amazon.com`). `ntpdate` is available |

## Display
- Driver: Lab126 **einkfb** (`/dev/fb0` id `eink_fb`). Diags mode uses the newer `mxc_epdc_fb`, which reports different values (stride 608, virtual 608x4480); ignore those.
- 600x800, 8 bpp, line_length **600**, yoffset 0, rotate 0. About 16 gray levels on the panel; the darker half of a 0-255 ramp looks almost the same.
- **Inverted in memory: 0 = white, 255 = black.** (`fbgrab` inverts back for screenshots.)
- Refresh ioctls (plain `_IO`, argument by value or raw pointer):
  - `0x46db` FBIO_EINK_UPDATE_DISPLAY(fx)
  - `0x46dd` FBIO_EINK_UPDATE_DISPLAY_AREA(&{x1,y1,x2,y2,fx,buffer=NULL})
  - `0x46e1` FBIO_EINK_CLEAR_SCREEN
  - fx: 0 partial, 1 full, 2 fast, 3 slow (always flashes).
- Measured: an area refresh call returns in about 24 ms, a full slow one in about 73 ms. The call is async; the panel finishes later.
- `/proc/eink_fb/update_display` also exists. There's no MXCFB/waveform control in main boot.
- After a key press, Amazon's UI takes **1.4-1.8 s** to start redrawing.

## Buttons (`/dev/input`)
| dev | name | keys (code) |
|---|---|---|
| event0 | `tequila-keypad` | home 102, menu 139, back 158, keyboard 29, left page keys: prev **193** / next **104**, right page keys: prev **109** / next **191** |
| event1 | `fiveway` | up 103, down 108, left 105, right 106, select 194 |
| event2 | `volume` | 114/115 advertised; there are no volume buttons on the K4 |

- The power button is **not** an input device: it goes through the PMIC to `powerd`.
- `event0` also sends EV_MSC/MSC_SCAN events, so filter on EV_KEY.
- Events are 16 bytes (32-bit timeval). musl's time64 `struct input_event` doesn't match, so `k4keys` defines its own.
- Writing raw events to `/dev/input/eventN` injects key presses that the UI reacts to (`k4press`).

## Power
- `powerd` states: active → screenSaver (after `t1_timeout` = 600 s) → suspend.
  - `lipc-set-prop com.lab126.powerd touchScreenSaverTimeout 1` resets the idle timer (only works while active).
  - `preventScreenSaver 1` also blocks the power button.
  - `powerd_test -p` simulates a power button press.
- Battery: `/sys/devices/system/yoshi_battery/yoshi_battery0/` (`battery_capacity`, `battery_mAH`, `battery_lmd`, ...) or `gasgauge-info -c`.
  A 13-year-old cell reported about 800 mAh full capacity.
- RTCs: `rtc0` = mxc_rtc, `rtc1` = pmic_rtc. `/sys/devices/platform/mxc_rtc.0/wakeup_enable` exists (wake-from-suspend: untested). There's no `rtcwake`.

## Firmware updates and Amazon
- 4.1.4 is the final K4 firmware.
- Updates are `.bin` bundles that `otaup` checks against the keys in `/etc/uks/*.pem` (the jailbreak adds `pubdevkey01.pem`).
- OTA is queued via `todo-g7g.amazon.com`. Amazon service hosts live in `/opt/amazon/ebook/config/*.conf`.
