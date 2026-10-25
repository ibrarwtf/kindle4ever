# Research: drawing on the K4 e-ink screen (2026-10-25)

> Research notes from before kindle4ever was built (web sources, with links). What was later verified on a device is in [../hardware.md](../hardware.md) and [../findings.md](../findings.md).

Web research only; nothing here was tested on a device unless marked.

## Key finding: K4 main boot uses the legacy **einkfb** API, not mxcfb
- Even though fb0 is named `mxc_epdc_fb`, on main boot the K4 runs in "K3 compatibility mode" with Lab126's einkfb driver. Diags uses mxcfb.
  - geekmaster: https://www.mobileread.com/forums/showthread.php?p=2061310
- KOReader uses `ffi/framebuffer_einkfb` for Kindle4: https://raw.githubusercontent.com/koreader/koreader/master/frontend/device/kindle/device.lua
- FBInk detects K4 (usid 0x0E Tequila, 0x23 Sauza) and sets `isKindleLegacy`, which selects the einkfb path at runtime: https://raw.githubusercontent.com/NiLuJe/FBInk/master/fbink_device_id.c
- `MXCFB_SEND_UPDATE` on K4 main boot is unconfirmed, and no maintained tool uses it. **Don't use it.**

## einkfb API (from FBInk eink/einkfb.h)
https://raw.githubusercontent.com/NiLuJe/FBInk/master/eink/einkfb.h
```c
#define FBIO_EINK_UPDATE_DISPLAY      _IO('F', 0xdb)  // 0x46db, arg = fx_type (by value)
#define FBIO_EINK_UPDATE_DISPLAY_AREA _IO('F', 0xdd)  // 0x46dd, arg = update_area_t *
#define FBIO_EINK_CLEAR_SCREEN        _IO('F', 0xe1)  // 0x46e1, arg = 0 screen | 1 buffer | 2 screen-not-buffer
#define FBIO_EINK_GET_DISPLAY_ORIENTATION _IO('F', 0xf1)
struct update_area_t { int x1, y1, x2, y2; fx_type which_fx; uint8_t *buffer; /* NULL = from fb */ };
fx_update_partial=0, fx_update_full=1, fx_update_fast=2, fx_update_slow=3, fx_flash=20, fx_invert=21
```
- FBInk's refresh_legacy: full screen → `UPDATE_DISPLAY(fx)`, region → `UPDATE_DISPLAY_AREA(&area)`.
- Also available: `/proc/eink_fb/update_display` (0 CLS, 1 PART, 2 FULL, 3 AREA…). No built-in delays on K4.

## Pitfalls
1. **Inverted palette: 0 = white.** Write `255 - gray`.
2. **Stride**: use `line_length` from FBIOGET_FSCREENINFO (we measured 608), never xres. Check `yoffset` (virtual 608x4480) and orientation.
3. **Identical frames get dropped** by the driver. To force a real flash, use `fx_update_slow` (3) or `CLEAR_SCREEN`.
   - KOReader PR: https://github.com/koreader/koreader-base/pull/2481 (tested on K3)
4. `fx_update_full` through UPDATE_DISPLAY_AREA often doesn't flash. For flashes, use the full-screen UPDATE_DISPLAY.
5. **No wait-for-complete** on einkfb. Updates are async, so sleep yourself. Our `k4wait` only sees the fb memory, not the panel.
6. **The framework draws over us.**
   - Stop it: `/etc/init.d/framework stop` / `start`.
   - Pause it: `killall -STOP cvm` / `-CONT`. After resuming, KOReader does `echo 'send 139' > /proc/keypad` twice to force a redraw.
   - pillow / `stop lab126_gui` are FW5-only.
   - KOReader also SIGSTOPs `volumd` (USB mass storage).
7. Screensaver: preventScreenSaver (done). RTC wake: `/sys/devices/platform/mxc_rtc.0/wakeup_enable` + `echo mem > /sys/power/state` (kindle-dash).
8. Ghosting: full flash every ~4 partials (kindle-dash), worse in the cold.

## Options
| Option | Notes |
|---|---|
| Own C (mmap + einkfb ioctls) | About 150 lines for blit + refresh. The whole K4 API is tiny (no waveforms, no wait). |
| FBInk CLI | GPLv3+. Has K4 support, TTF text, images. Call it as a separate process to keep our code ours. Build with `make kindle` (not `legacy`). Prebuilt: https://www.mobileread.com/forums/showthread.php?t=299620 |
| eips | Already on the device. On K4 it can't position images (-x/-y broken) and has no rects. Full-screen PNGs only. https://wiki.mobileread.com/wiki/Eips |
| kindle-dash / Petroff weather | Server renders a 600x800 gray PNG, the device runs `eips -g` (+ `-f` every N). Both used a K4. |

## Unconfirmed
- MXCFB on K4 main boot. eips `-w`. fx_update_slow on K4. FBInk prebuilt on K4. Meaning of yres_virtual 4480 / rotate=1.
