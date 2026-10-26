# Recovery

From mildest to most drastic. **Tested** = done on a real K4 NT (FW 4.1.4) while building kindle4ever.

## Before you need this
- **Back up** the system partitions to your computer once you have SSH (about 480 MB, skips the book partition):
  ```sh
  tools/k4 sh 'sync; dd if=/dev/mmcblk0 bs=512 count=978944 2>/dev/null' > backup.img
  ```
  Partitions (512-byte sectors): p1 rootfs @65536 len 716800 · p2 diags @782336 len 131072 · p3 /var/local @913408 len 65536 · p4 userstore @978944.
  The image holds device-unique data (serial, MAC, keys). Keep it private and never restore it onto a different Kindle.
- Keep `tools/fetch-vendor.sh` downloads: the jailbreak and USBNetwork **uninstaller** .bins live there.

## Level 0: screen or UI stuck, SSH works (risk: none)
- Wake from the screensaver: `tools/k4 sh powerd_test -p` (tested). **Never `powerd_test -h`**: it is not help, it simulates a power-button *hold*, which put the device to sleep with Wi-Fi off (tested, by accident).
- Auto-sleep is held off by `boot.sh`, which resets the idle timer every 2 min while the device is active.
  Don't use `lipc-set-prop com.lab126.powerd preventScreenSaver 1`: powerd then **ignores the power button** (tested).
- Give the screen back to Amazon's UI after app mode: `tools/k4 sh k4app off` (tested). Restart the UI: `/etc/init.d/framework restart`.
- Reboot: `tools/k4 sh 'sync; (sleep 1; reboot) &'` (tested). SSH is back in about 60 s, the UI in about 2 min.
  **If USB is plugged in, the computer re-mounts the drive after boot, and the Kindle turns Wi-Fi off.**
  `tools/find-kindle.ps1` / `.sh` ejects it and finds the device again (tested on Windows).

## Level 1: SSH unreachable (risk: none to low)
1. Run `tools/find-kindle.ps1` (Windows) or `tools/find-kindle.sh`. It ejects the drive if mounted, re-finds the IP by MAC and checks port 22 (tested).
2. Asleep? Wi-Fi drops after a while in the screensaver. Press power once.
3. Restart from the device: Menu > Settings > Menu > Restart.
4. Broken USBNetwork config? Over USB, fix `usbnet/etc/config` on the drive (UNIX line endings!) or copy `config.default` over it.
   To stop autostart, rename `usbnet/auto` to `DISABLED_auto`.
5. Wi-Fi trouble after `--amazon-block`: `tools/uninstall.sh` removes the block. The original hosts file is also kept as `/etc/hosts.k4-orig`.

## Level 2: UI won't come up / boot loop, device alive (risk: low)
- Suspect kindle4ever's boot hook? Create `kindle4ever/DISABLE_BOOT` on the USB drive and restart: boot.sh is skipped.
  Remove it fully: `tools/uninstall.sh`, or by hand `mntroot rw; rm /etc/rc5.d/S97k4-boot /etc/init.d/k4-boot; mntroot ro`.
- USBNetwork starts sshd before the UI (`usbnet/auto`), so SSH usually still works when the UI doesn't.
- Diags mode: put an empty `ENABLE_DIAGS` file on the drive root and restart. You get a text menu running from the separate diags partition (this is how the jailbreak runs; tested).
- Uninstall the hacks: the USBNetwork uninstaller .bin, then the jailbreak uninstaller .bin, via Menu > Settings > Menu > Update Your Kindle.

## Level 3: bricked (no boot, no USB drive) (risk: high)
Untested here. Read the threads fully first.
- **Charge first, for many hours on a wall charger.** A deeply discharged K4 looks bricked: on our unit the drive showed as "No Media" until it had some charge.
- USB downloader mode: plug in USB, hold power until the LED goes off, hold 5-way Down, release power, then release Down. Then MfgTool profiles or Kubrick. https://www.mobileread.com/forums/showthread.php?p=1972279
- Kubrick, a Linux live CD/USB that re-flashes a K4 (it puts 4.1.1 back on): https://www.mobileread.com/forums/showthread.php?t=206064.
  Your own backup image can be written back at the offsets above.
- "Simple debricking" thread: https://www.mobileread.com/forums/showthread.php?t=170929
- Serial console `ttymxc0` at 115200 baud: unpopulated pads on the board (GND, RxD, TxD). Needs the case opened and a level shifter (see the thread). https://www.mobileread.com/forums/showthread.php?p=1940010

## Rules that keep you out of trouble
- **Never factory reset or deregister.** Amazon ended K4 support on 2026-05-20; a reset K4 reportedly can't be registered again.
- Only write to `/` (p1) between `mntroot rw` and `mntroot ro`. kindle4ever keeps its files in `/mnt/us/kindle4ever`.
- Don't fill `/var` (32 MB tmpfs) or `/var/local` (p3, ~31 MB). Big temp files go under `/mnt/us`.
- Nothing important should run from `/mnt/us` while a computer might mount the drive: it disappears, and processes using it get killed.
- Don't boot with a custom `.bin` left on the drive root. Only install `.bin`s via Update Your Kindle.
