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

## Amazon block (`tools/install.sh --amazon-block`)
- Appends a marked block to `/etc/hosts` that maps the Amazon service hosts found in `/opt/amazon/ebook/config/*` and `/etc/sysconfig/ntp` to 127.0.0.1.
  Source: `device/rootfs/etc/hosts.amazon-block`. The original file is saved as `/etc/hosts.k4-orig`, and `tools/uninstall.sh` removes the block.
- Left alone on purpose: wifid's anonymous connectivity probe (S3/CloudFront, generic browser UA). wifid does its own DNS lookups and
  injects the result into curl, so hosts entries wouldn't affect it anyway, and breaking the probe risks Wi-Fi drops.
- Verified: the todo server gets connection refused. A Wi-Fi off/on cycle reconnected in about 16 s. After a reboot the UI and Wi-Fi were fine, and boot.sh synced the time from pool.ntp.org.
- Not done: renaming `/etc/uks`. It would block OTA a second way, but also every `.bin` you install yourself.
