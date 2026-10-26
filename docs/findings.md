# Findings: online claims vs. what the device actually shows

Checked on a K4 NT (FW 4.1.4, main boot) over SSH, October 2026. Sources for the claims are in [research/](research/).
Tip: copy device files to your computer to search them (`tools/k4 sh 'tar -cf - /etc /opt/amazon/ebook/config' | tar -xf -`).
BusyBox 1.7.2's `grep` has no `-E`, so on-device regex searches silently find nothing.

| Claim (source) | On the device | Verdict |
|---|---|---|
| K4 main boot uses the legacy einkfb, not mxcfb | fb0 id `eink_fb`, `/proc/eink_fb/update_display` exists | **True** |
| fb line_length 600, no padding (2011 forum) | line_length 600, 600x800, yoffset 0, rotate 0 | **True** (608 is what diags mode reports) |
| K4 has no `/proc/eink_fb/update_display` (later forum post) | It exists | **False** for the tested unit |
| 0 = white (inverted palette) | Blank fb rows are all 0, and k4draw output looks right on the panel | **True** |
| `event0` sends an extra "code 4" before each key (sixfoisneuf) | event0 advertises `MSC=10` = EV_MSC/MSC_SCAN. "Code 4" is the standard scancode event, not a key. | **Misread.** Readers should just filter on EV_KEY. |
| Key codes: next 104/191, prev 109/193, etc. (forum) | Matches injection and physical tests: left side prev 193 / next 104, right side prev 109 / next 191 | **True** |
| SysV init, `/etc/init.d/framework stop` | SysV, `/etc/init.d/framework` present | **True** |
| pillow / upstart don't exist on K4 | No upstart | **True** |
| `netwatchd` kills connections | Has a K70 kill link in rc5 and **isn't running** | **Doesn't apply** |
| `WIFI_NO_NET_PROBE` file disables the Wi-Fi probe | String not in K4 `wifid` (that's a Touch/PW thing). wifid has a `-n` "internet connectivity not required" flag. | **Doesn't apply**. `-n` noted for later. |
| Screensaver timeout 600 s in kdb | `kdb get system/daemon/powerd/t1_timeout` = 600 | **True** |
| Stock curl/wget can't do modern TLS | OpenSSL 0.9.8j (2009), curl 7.21.4: github.com, open-meteo, 1.1.1.1 fail (rc 35). google.com, example.com work. | **True** (a few lenient sites still work) |
| `rtcwake` not on stock K4 | Not present | **True** |
| RTC wake via `mxc_rtc.0/wakeup_enable` (kindle-dash) or `rtc1/wakealarm` (x-magic) | `mxc_rtc.0/wakeup_enable` exists. rtc0 = mxc_rtc, rtc1 = pmic_rtc. | **Plausible**, untested |
| Battery at `yoshi_battery0/battery_capacity`, `gasgauge-info -c` | Both work | **True** |
| Battery 1800 vs 890 mAh (conflicting) | `battery_mAH=732` (current), `battery_lmd=808` (learned full capacity) | This (old) unit: about 800 mAh. **Expect short always-on life.** |
| Cron at `/etc/crontab/root` (fnordig) vs `/etc/crontabs/root` | `/etc/crontab/root` | fnordig right |
| `/etc/uks` rename blocks OTA (U007) | `otaup` verifies bundles with `/etc/uks/*.pem` and errors U007 | **True**, but it also blocks your own .bin installs |
| OTA comes via Amazon "todo" server | `TODO_SERVER=https://todo-g7g.amazon.com/FionaTodoListProxy/` | **True**. Blocked by `--amazon-block` (see below). |
| Clock syncs from Amazon | `/usr/sbin/updatetime`: ntpdate `ntp-g7g.amazon.com`, fallback HTTP Date from `kindle-time.amazon.com` | **True**. kindle4ever's boot.sh syncs from pool.ntp.org instead. |
| Amazon strips the Java dev keystore on contact | Not tested. kindle4ever doesn't use Kindlets/KUAL. | Irrelevant here |
| Don't factory reset (end of support) | — | **Adopted** as a rule |
| Power button | With `preventScreenSaver 1` set, syslog shows `Prevent screen saver set. Ignoring power button` | Use `touchScreenSaverTimeout` instead (boot.sh does) |
| `tphd`/`phd` phone home (forum lore, no K4 source) | `phd` runs on the K4: retries the todo server every 30-60 min, asks powerd for an RTC wakeup before suspend, listens on TCP 40317 | **True and worse than described**. `install.sh --amazon-off` disables it |
| RTC wake needs `rtcwake` or raw sysfs writes (kindle-dash) | powerd has a writable `rtcWakeup` property (`lipc-set-prop com.lab126.powerd rtcWakeup <s>`), which is what phd uses | **Simpler path exists**, see hardware.md |
| The K4 uses upstart (`initctl stop webreader`, kindle-dash) | SysV only; `webreader`/`browserd` are stopped via `lipc-set-prop com.lab126.pmond stop <name>` (browserd also needs `killall`) | **False** for the K4 |
| Removing the `loginfo` cron lines is safe, keep `tinyrot` (NiLuJe) | `/etc/crontab/root` matches the forum copy; `/var/local` is 32 MB mounted `sync` | **Agreed**, not changed by kindle4ever |
| Time zone can be set with a zoneinfo file at `/var/local/system/tz` (PW2 guide) | The symlink exists but the stock busybox ignores both it and `/etc/TZ`; only `TZ=IST-5:30` in the environment works | **Partly**: `install.sh --tz` sets the files and exports TZ |

## Amazon
Everything Amazon-related (what phones home, what `--amazon-block` and `--amazon-off` do, what stays) is in [amazon.md](amazon.md).
