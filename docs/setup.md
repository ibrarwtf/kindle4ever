# Setup: from a stock Kindle 4 NT to SSH + kindle4ever

Tested on a Kindle 4 Non-Touch (2012, black) with firmware **4.1.4**, from Windows 11 with Git Bash. The jailbreak supports 4.0.0 through 4.1.4.
Linux and macOS should work with the same scripts (`find-kindle.sh` instead of `.ps1`), but haven't been tested yet.

You do the physical steps (plug in, press buttons). Everything else is a command.
Each step has a risk level: **none** (reads only), **low** (changes the device, with a tested way back), **high** (can brick; not needed here).
Total time is about 30 minutes, most of it the Kindle rebooting.

> **Never factory reset or deregister the Kindle.** Amazon ended K4 support on 2026-05-20, and a reset K4 reportedly can't be registered again.

## 0. Your computer (risk: none)
- Git Bash (Windows) or any POSIX shell, plus `curl`, `unzip`, `python3` (or `python`), `ssh`.
- Check your firmware: on the Kindle, Menu > Settings. The version is at the bottom (e.g. `Kindle 4.1.4`).
  Note the **Wi-Fi MAC address** on page 2 (Device Info).

```sh
git clone https://github.com/ibrarwtf/kindle4ever && cd kindle4ever
tools/setup-toolchain.sh          # pinned Zig compiler into toolchain/ (sha256-checked)
tools/fetch-vendor.sh             # jailbreak + USBNetwork packages into vendor/ (sha256-checked)
ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/kindle4ever     # RSA: the Kindle's old dropbear has no ed25519
cp k4.env.example k4.env      # then set K4_MAC, K4_SUBNET, K4_SSH_KEY
tools/build.sh                    # k4draw, k4keys, k4fetch -> build/
```

## 1. Charge (risk: none)
Plug the Kindle in. If the battery was flat, the USB drive can show up with **no media** for a few minutes until it has some charge.
Wait for the "USB Drive Mode" screen.

## 2. Jailbreak (risk: low; undo with the jailbreak uninstaller .bin)
```sh
tools/stage-usb.sh /d jailbreak   # /d = where the Kindle drive is mounted (D: in Git Bash; /media/... or /Volumes/Kindle elsewhere)
```
This copies `data.tar.gz`, `ENABLE_DIAGS`, `diagnostic_logs/` and kindle4ever's `runme.sh`. The jailbreak runs `runme.sh` as root,
and it only reads system info into `/mnt/us/devinfo/`.

On the Kindle:
1. Eject the drive on your computer, then unplug.
2. Menu > Settings > Menu > **Restart**.
3. A text **diagnostics menu** appears. With the 5-way pad, choose **D) Exit, Reboot or Disable Diags**, then **R) Reboot System**.
   "FW Left" means left on the 5-way.
4. About 20 s later a jailbreak picture shows, then a normal boot. A document called **"You are Jailbroken"** should be in the library.

What it does: installs a developer key (`/etc/uks/pubdevkey01.pem`), so the Kindle accepts self-signed update packages. Nothing else.

## 3. SSH over Wi-Fi (USBNetwork) (risk: low; undo with the USBNetwork uninstaller .bin)
Plug in again, then:
```sh
tools/stage-usb.sh /d usbnet-install
```
Eject, unplug, then on the Kindle: Menu > Settings > Menu > **Update Your Kindle**. It installs and reboots.

Plug in again, then:
```sh
tools/stage-usb.sh /d usbnet-config
```
This writes `usbnet/etc/config` (SSH over Wi-Fi only, so the USB drive keeps working) and your public key, and enables start at boot.

Eject, unplug, then on the Kindle: Menu > Settings > Menu > **Restart**, then Settings > **Wi-Fi Networks** to join your network.

## 4. Find it and log in (risk: none)
```sh
powershell -File tools/find-kindle.ps1     # Windows
tools/find-kindle.sh                       # Linux/macOS
tools/k4 sh 'uname -a; cat /etc/prettyversion.txt'
```
`find-kindle` ejects the drive if it's mounted (**the Kindle turns Wi-Fi off while its drive is mounted**), finds the IP by MAC,
checks SSH, and writes `K4_HOST` into your `k4.env`.
Optionally, reserve that IP for the Kindle's MAC in your router.

## 5. Install kindle4ever on the Kindle (risk: low; undo with `tools/uninstall.sh`)
```sh
tools/install.sh --amazon-block --amazon-off --no-browser --tz Asia/Kolkata --start
```
- Copies the tools to `/mnt/us/kindle4ever/bin` and `boot.sh` to `/mnt/us/kindle4ever`.
- Installs a small boot hook: `/etc/init.d/k4-boot`, which runs `boot.sh` at every boot.
  `boot.sh` keeps the Kindle from auto-sleeping (the power button still works) and syncs the clock.
- `--amazon-block`: blocks Amazon's Kindle services in `/etc/hosts` (OTA, store, registration, telemetry, Amazon time).
- `--amazon-off`: stops Amazon's phone-home and transfer daemons (they retry every 30-60 min and wake the device from sleep to do it)
  and points the stock clock sync at `pool.ntp.org`. Everything Amazon-related is explained in [amazon.md](amazon.md).
- `--no-browser`: stops the experimental web browser (about 21 MB of RAM). `--tz <zone>`: time zone (the stock system is UTC).
- Kill switch: create `kindle4ever/DISABLE_BOOT` on the USB drive. Undo everything: `tools/uninstall.sh`.

## 6. Check it works (risk: none)
```sh
tools/k4 shot                    # screenshot -> shots/latest.png
tools/k4 press home down select  # press keys (waits for the screen after each)
tools/k4 sh 'k4draw text 40 700 30 0 "Hello from kindle4ever"'
tools/k4 sh 'k4fetch -o /dev/null https://example.com && echo https works'
tools/doctor.sh                 # full self-test; --markdown for a report you can paste into an issue
```
No device at hand? `tools/sim` runs the same `k4draw` on your computer and shows what the panel would display.

## 7. Back up (risk: none)
Do it now, while everything works. See [recovery.md](recovery.md#before-you-need-this).

## Contributing: leak check before every push
```sh
printf '#!/bin/sh\nexec tools/check-public.sh --hook\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push
```
Put your own exact values (serial, MAC, IP prefix, Wi-Fi name, key fingerprint) one per line in a file **outside** the repo,
and point `K4_LEAKLIST` at it. CI runs the generic checks on every push.

## Gotchas we hit
- The drive mounted on a computer means Wi-Fi off and `/mnt/us` gone on the device. Processes running from `/mnt/us` get killed.
- After a reboot with USB plugged in, the computer mounts the drive again, so run `find-kindle` again.
- BusyBox 1.7.2: no `grep -E`, no `nohup`, and `sed 's/\r//'` deletes the letter `r`. Strip CRs on your computer, as `tools/k4 push` does.
- `preventScreenSaver 1` makes powerd ignore the power button. `boot.sh` uses `touchScreenSaverTimeout` instead.
- SSH sessions get `PATH=/usr/bin:/bin`. `eips`, `lipc-*` and `mntroot` live in `/usr/sbin`, and `tools/k4` sets a full PATH.

## Simulator
Most UI work needs no Kindle. Three levels:
1. `tools/sim <k4draw command>` draws into `build/sim/screen.raw`; `tools/sim show` exports it as the panel would show it.
2. `tools/sim serve` opens http://localhost:8470 with the screen, the 13 buttons and keyboard shortcuts (arrows, Enter, [ ] , .
   for page keys, h m b k). Presses are queued for the simulated `k4keys`; refreshes recorded by k4draw are outlined on the screen
   (dashed = partial, red = flash), so you can see what a UI change costs the panel.
3. `tools/twin.sh` (Linux or WSL, as root) runs the real scripts: `setup [FONTDIR]` links `/mnt/us/kindle4ever` to a staging copy of this
   checkout with simulator stubs for lipc, powerd and the battery gauge, then `run device/bin/k4home` or `run apps/livestation/app.sh`.
   Give `setup` a folder holding your own copy of the Kindle's `/usr/java/lib/fonts` so text measures exactly as on the device.
   `arm-setup <backup.img>` unpacks the Kindle's root filesystem from your `dd` backup and `arm <cmd>` runs commands in it under
   qemu-arm: the Kindle's own busybox 1.7.2 sh, awk and sed, which differ from GNU tools in ways that only show up there.
   The rootfs is Amazon's and device-specific: it stays on your machine.

   On Windows the viewer runs natively (`tools/sim serve`) and the twin runs in WSL on the same checkout, so they share `build/sim`:
   `wsl -d Ubuntu -u root -- sh /mnt/c/.../tools/twin.sh run device/bin/k4home` in its own terminal, then press keys in the browser.
   The twin sets `LC_ALL=C` because the Kindle has no locale; GNU awk in a UTF-8 locale would count characters where busybox counts
   bytes and the train art would fall apart.
4. `tools/ci-sim.sh` (Linux, also run by CI) is the regression suite built on all this: busybox parses every script, k4home and the
   Live station app draw on the simulated screen, and the ARM k4draw under qemu must render exactly the host build's pixels.
