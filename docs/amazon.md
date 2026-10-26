# Amazon and this Kindle: what talks to Amazon, and what kindle4ever turns off

Amazon ended Kindle 4 support on 2026-05-20. Firmware 4.1.4 is final, the store and registration are gone for this model,
and a device that is factory reset can reportedly never be registered again. There is nothing left to gain from letting the
Kindle talk to Amazon, so kindle4ever gives you two switches to stop it, both reversible with `tools/uninstall.sh`:

```sh
tools/install.sh --amazon-block --amazon-off     # usually together with --no-browser --tz <zone>
```

Everything below was checked on a K4 NT running 4.1.4 over SSH in October 2026 (`docs/findings.md` has the method).

## What the stock system does with Amazon

| Component | What it is | How it reaches Amazon | Stopped by |
|---|---|---|---|
| `phd` (Phone-Home Daemon, `/usr/sbin/phd`) | Polls the "todo" server for OTA updates, sync and device messages. Started from `/etc/rc5.d/S75phd`, supervised by `pmond`. On failure it retries every **30 min, then 60 min**. Before each suspend it asks `powerd` for an **RTC wakeup**, so a sleeping Kindle wakes up to phone home. It also listens on TCP port **40317** (the "TPH" push port; iptables only lets it in on the 3G interface, which the K4 doesn't have). | `todo-g7g.amazon.com` over HTTPS | `--amazon-off` (start link removed, daemon stopped) |
| `tmd` (Transfer Manager Daemon) | Downloads books, updates and the like for the framework. | Store/CDN hosts from `/opt/amazon/ebook/config/*.conf` | `--amazon-off` |
| Java framework (`cvm`) | Registration, store, sync, collections, the "special offers" rotation (this unit never got ads: no `/var/local/adunits`). | `firs-`, `cde-`, `det-`, `todo-g7g.amazon.com`, `kindle.amazon.com`, ... | `--amazon-block` (hosts file). The UI itself stays; `k4app on` stops it when an app wants the screen |
| `/usr/sbin/updatetime` | Clock sync: `ntpdate ntp-g7g.amazon.com`, fallback HTTP `Date:` from `kindle-time.amazon.com`, then `hwclock -w`. | NTP and HTTP | `--amazon-off` rewrites `/etc/sysconfig/ntp` to `pool.ntp.org`, so the stock mechanism keeps working. `boot.sh` syncs from the pool too |
| `wifid` connectivity probe | After connecting, fetches `spectrum.s3.amazonaws.com/kindle-wifi/wifistub.html` through `dogvgb9ujhybx.cloudfront.net`, and again every 600 s (`PROBE_SYNC`). Anonymous. | S3 / CloudFront, with its own DNS lookup that bypasses `/etc/hosts` | **Left alone**: breaking the probe risks Wi-Fi drops. The hosts (`PROBE_HOST`, `PROBE_DOMAIN`, `PROBE_PATH`) are kdb keys if you ever want to point it at your own server |
| `otaup` + `/etc/init.d/updater` | Installs `update*.bin` files found on the USB drive at boot, verifying them against `/etc/uks/*.pem`. | Nothing on its own; OTA bundles arrive through `phd`/`tmd` | Nothing. **Don't rename `/etc/uks`**: it also blocks the jailbreak's `.bin` installers |
| `webreader`, `browserd` | The experimental web browser (WebKit, about 21 MB of RAM while idle). Not Amazon-specific, but useless once you have `k4fetch`. | Whatever you browse | `--no-browser` |
| Firewall | `/etc/sysconfig/iptables`: INPUT drops everything on Wi-Fi except replies and (USBNetwork adds) port 22. | Inbound is already closed | Nothing to do |
| Not running on this board | `wan`, `wand`, `mcsd` (3G parts), `testd`, `netwatchd` | | Nothing to do |

After `--amazon-off --no-browser` the only listening sockets are sshd (22) and syslog on localhost (`netstat -tuln`).

## `--amazon-block`: hosts file
Appends a marked block to `/etc/hosts` (source: `device/rootfs/etc/hosts.amazon-block`) that points Amazon's Kindle service hosts
at 127.0.0.1, so connections fail instantly instead of timing out. The original is kept as `/etc/hosts.k4-orig`.
Verified: the todo server gets "connection refused", Wi-Fi reconnects normally, boot is unchanged.

## `--amazon-off`: daemons and clock
- Stops `phd` and `tmd` through their supervisor (`lipc-set-prop com.lab126.pmond stop <name>`) and removes their start links
  `/etc/rc5.d/S75phd` and `S90tmd`. The removed links are listed in `/etc/rc5.d/.k4-disabled`; `uninstall.sh` recreates them.
- Rewrites `NTP_SERVER` in `/etc/sysconfig/ntp` to `pool.ntp.org` (backup: `ntp.k4-orig`). Verified: `/usr/sbin/updatetime` then
  syncs from the pool and sets the RTC.
- The binaries stay on the read-only root filesystem (80 KB and 214 KB). Deleting them gains nothing; disabling is enough.

## `--no-browser`
Same mechanism for `webreader` and `browserd` (`S93webreaderd`, `S94browserd`). `browserd` ignores pmond's stop, so it is
also killed with `killall`. Menu, Experimental, Web Browser will no longer work; `uninstall.sh` plus a reboot brings it back.

## `--tz <zone>`
Not Amazon-related, but the stock system runs in UTC with a dangling `/etc/localtime` and no zoneinfo. The flag writes a TZif file
to `/var/local/system/tz`, the POSIX string (for example `IST-5:30`) to `/etc/TZ`, and one `export TZ=...` line to `/etc/profile`.
The stock busybox reads neither file, so `boot.sh`, `tools/k4` and login shells export `TZ` from `/etc/TZ`.

## What we deliberately keep
- The Java framework and its reader: still the fallback UI, and `k4app` hands the screen back to it.
- `pmond`, `powerd`, `cmd`, `wifid`, `volumd`, `lipc-daemon`, `cron`/`tinyrot`: power, Wi-Fi, USB drive mode and log rotation.
  Without `tinyrot` the 32 MB `/var/local` fills up and the device stops booting.
- The wifid probe (see above).

## Undo
`tools/uninstall.sh` restores the hosts file, the rc5.d links, `/etc/sysconfig/ntp`, `/etc/TZ`, `/etc/profile` and removes the zone
file. Reboot afterwards so the daemons start again.
