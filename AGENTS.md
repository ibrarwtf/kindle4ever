# AGENTS.md

How to use kindle4ever, and how to build on it. Device facts: [docs/hardware.md](docs/hardware.md). Tool reference: [docs/tools.md](docs/tools.md).

## Use the tooling
From your computer, with `K4_HOST` etc. set (see `k4.env.example`):
```sh
tools/k4 sh '<cmd>'          # run on the Kindle (kindle4ever tools are on PATH)
tools/k4 press home down     # press keys; waits for the screen to change and settle
tools/k4 shot out.png        # screenshot (framebuffer memory)
tools/k4 run script.sh       # copy a script over and run it
tools/doctor.sh             # check everything works
tools/sim <k4draw args>      # same drawing on your computer, no device needed
```
Keys: `home menu back kbd lprev lnext rprev rnext up down left right select power`.
If the Kindle is unreachable, run `tools/find-kindle.ps1` / `.sh`. A mounted USB drive turns its Wi-Fi off.

## Build on top
- **A script app**: a shell script that calls `k4app on`, draws with `k4draw`, reads buttons with `k4keys`, fetches with `k4fetch`, then `k4app off`.
  Example: `device/bin/k4about`. Try it on the PC first with `tools/sim`.
- **Try it without the device**: `tools/sim serve` (viewer with buttons) plus, on Linux/WSL as root, `tools/twin.sh setup` once and
  `tools/twin.sh run device/bin/k4home` or `tools/twin.sh run apps/livestation/app.sh`. Apps should read `LIVESTATION_FIXTURE`-style
  variables for offline data. `tools/twin.sh arm` runs the Kindle's real busybox from your backup image when shell semantics matter.
- **A home-screen app**: a folder with `app.sh` (comment lines `# name: Label` and `# version: x.y.z`), optionally `icon.sh CX CY` printing k4draw
  commands for its icon, installed with `tools/k4 app <folder>` to `/mnt/us/kindle4ever/apps/<name>/`. `k4home` shows it as a cell;
  when picked, it runs with the screen already yours and should return when the user presses Back or Home. Landscape apps set
  `K4DRAW_ROTATE=90` and draw on 800x600. Keep heavy lifting in awk/sh plus the k4 tools: `apps/livestation` refreshes a full board
  in about a second of CPU. Personal settings go in a `*.conf` next to the app (not copied by `k4 app`, push it yourself).
- **A C app**: put it in `src/<name>/`, add a line to `tools/build.sh`, and build static with `tools/kcc`. Copy code from `k4draw`/`k4keys` as needed (static binaries, no shared libs).
- **Ship it**: put scripts in `device/bin/` and binaries in `build/`, then `tools/k4 deploy` (or `tools/install.sh`). Everything lands in `/mnt/us/kindle4ever/bin`.
- **Before you change the device**: back up ([docs/recovery.md](docs/recovery.md)), only touch `/` between `mntroot rw` and `mntroot ro`, and keep big files out of `/tmp` and `/var`.
- **Don'ts**: `preventScreenSaver 1` (it disables the power button); stripping CRs on the device (BusyBox `sed` eats `r`); factory resetting the Kindle.

## Gotchas (each cost real time once)
- The Kindle sleeps 3 min after the last key by default and only the power button wakes it. Run `tools/k4 hold` before a
  session of deploys, and `tools/k4 wait` after asking for the button. Liveness = SSH; the firewall drops ping.
- BusyBox 1.7.2 sh/awk: `or`, `and`, `xor` are built-in functions (not variable names); `sleep` takes whole seconds (use
  `usleep`); `case $(cmd) in` nested in another case fails to parse; awk counts bytes, so run GNU awk with `LC_ALL=C` when
  testing on a PC. `sh -n` on the device (or `tools/twin.sh arm "sh -n file"`) catches the parse errors; `tools/ci-sim.sh` does it in CI.
- A shell `trap` only runs after the current foreground command ends, so a signal cannot interrupt a blocked `k4keys -1`.
  Act in the listener itself (k4home keeps its selection in a file for that).
- `powerd_test -h` is a power-button *hold*, not help. `lipc-set-prop powerd rtcWakeup` is only accepted during `readyToSuspend`.
- Scripts run from `/mnt/us` die when a PC mounts the USB drive and are read lazily by the shell: copy to `/var/run` and exec that (k4home does).
- Device scripts hard-code `/mnt/us/kindle4ever`; the twin provides it, CI relocates PATH with sed. Keep new device paths behind variables.
