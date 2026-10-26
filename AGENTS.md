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
- **A home-screen app**: a folder with `app.sh` (comment lines `# name: Label` and `# version: x.y.z`), optionally `icon.sh CX CY` printing k4draw
  commands for its icon, installed with `tools/k4 app <folder>` to `/mnt/us/kindle4ever/apps/<name>/`. `k4home` shows it as a cell;
  when picked, it runs with the screen already yours and should return when the user presses Back or Home. Landscape apps set
  `K4DRAW_ROTATE=90` and draw on 800x600. Keep heavy lifting in awk/sh plus the k4 tools: `apps/livestation` refreshes a full board
  in about a second of CPU. Personal settings go in a `*.conf` next to the app (not copied by `k4 app`, push it yourself).
- **A C app**: put it in `src/<name>/`, add a line to `tools/build.sh`, and build static with `tools/kcc`. Copy code from `k4draw`/`k4keys` as needed (static binaries, no shared libs).
- **Ship it**: put scripts in `device/bin/` and binaries in `build/`, then `tools/k4 deploy` (or `tools/install.sh`). Everything lands in `/mnt/us/kindle4ever/bin`.
- **Before you change the device**: back up ([docs/recovery.md](docs/recovery.md)), only touch `/` between `mntroot rw` and `mntroot ro`, and keep big files out of `/tmp` and `/var`.
- **Don'ts**: `preventScreenSaver 1` (it disables the power button); stripping CRs on the device (BusyBox `sed` eats `r`); factory resetting the Kindle.
