# Journey: how kindle4ever came to be

An AI coding agent (Claude Code, on Windows) took an unused Kindle 4 NT from "nothing on it" to "the agent deploys code, sees the screen,
presses buttons and recovers the device on its own" in one long session in October 2026. The human only plugged things in and pressed buttons.
These are the steps and the mistakes, so you don't repeat them.

1. **Identify.**
   - Over USB the drive showed "No Media": the battery was flat. After a few minutes of charging it mounted.
   - The drive holds no firmware info. The serial prefix `9023` and the Settings screen gave the model (K4 NT, black) and firmware (4.1.4).
2. **Research, then read the code.**
   - MobileRead's wiki says the K4 diags jailbreak works up to 4.1.4.
   - The payload script was read before running it: it installs one key, runs an optional `runme.sh`, cleans up and reboots.
   - We used `runme.sh` to dump system info as root during the jailbreak. That dump came from **diags mode**, though: its framebuffer numbers (stride 608) turned out to be wrong for normal boot (600).
3. **Jailbreak** went smoothly. A missing `diagnostic_logs/device_info.xml` is the known pitfall.
4. **USBNetwork over Wi-Fi.** We configured SSH-only mode, so USB mass storage keeps working as a fallback, with key auth and autostart.
   - First surprise: **while the drive is mounted on the computer, the Kindle's Wi-Fi is off.** That led to `find-kindle`, which ejects the drive and then finds the device by MAC.
5. **Backup** of the boot area plus the system partitions: 501 MB, checksum verified on both ends.
   - Mistake: an early command `tee`'d the stream into `/tmp` and filled the 32 MB `/var` for a minute. Lesson: big files only under `/mnt/us`.
6. **Screen, keys, run.**
   - Key codes were read off `/proc/bus/input/devices` bitmaps, then injected by writing raw `input_event`s to `/dev/input/eventN`, and confirmed with screenshots.
   - The screensaver swallowed key events. We fixed that by keeping the device awake.
   - Fixed sleeps were unreliable, because the UI takes 1.4-1.8 s to react, so we wrote `k4wait`: it waits for the framebuffer to change, then settle.
   - The `\r`-stripping `sed` on the device chopped trailing `r`s off scripts: BusyBox 1.7.2 doesn't know `\r`.
7. **Boot hook.**
   - The first version ran its script from `/mnt/us` and **got killed when Windows mounted the drive**. It now copies itself to tmpfs first.
   - A remote reboot then went end to end with no human involved.
8. **Compiler.** Zig cross-compiles static musl binaries for armv7 from Windows, with no WSL or Linux VM needed. That avoids the device's 2010-era glibc.
9. **Research vs reality.**
   - Two web-research passes, then every claim was checked on the device ([findings.md](findings.md)).
   - Most claims held. A few were wrong for this unit, or belonged to the Kindle Touch.
   - A big one: in normal boot the K4 uses the legacy einkfb interface, not mxcfb.
10. **Amazon block.** Amazon service hosts go to localhost via `/etc/hosts`. The Wi-Fi probe stays untouched, because it bypasses hosts anyway. The clock now syncs from pool.ntp.org.
11. **Power button.** The human reported that the power button had stopped working. syslog: `Prevent screen saver set. Ignoring power button`.
    We switched from `preventScreenSaver` to resetting the idle timer (`touchScreenSaverTimeout`), which the device rejects while asleep, so it never overrides a user lock.
12. **k4draw.**
    - Our own e-ink drawing: mmap, inverted gray, three einkfb ioctls, stb_truetype and stb_image. Confirmed on the panel with a photo.
    - App mode (`k4app`) stops Amazon's UI. Keys then redraw nothing, and `k4app off` brings it back.
13. **k4keys.**
    - Reads evdev directly. musl's time64 `input_event` doesn't match the 2.6.31 kernel's 32-bit layout, so it uses its own struct.
    - A physical test of all 13 buttons found that our left/right page-key pairs were crossed.
14. **k4fetch.** BearSSL with 16 built-in roots, TLS 1.2. It reaches the modern sites the stock OpenSSL 0.9.8j can't.
    The kernel has no IPv6, and BearSSL 0.6 can't match certificates issued to IP addresses.

What made the agent effective: a screenshot + key injection + wait-for-screen loop, a backup and a written recovery ladder before risky steps,
a kill switch on anything that runs at boot, and asking the human for a photo when the framebuffer wasn't proof enough.
