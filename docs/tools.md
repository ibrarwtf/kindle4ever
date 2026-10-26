# Device tools

The command-line contract of the tools installed in `/mnt/us/kindle4ever/bin`: options, output and exit codes.
Apps and scripts may rely on these. Changing them is a breaking change, noted in CHANGELOG.md.
Generated from each tool's `--help` by `tools/gen-tools-doc.sh` (CI checks it's current).

## k4draw

```
usage: k4draw [-n] [-F] <command> [args]     run one command
       k4draw [-n] [-F] -                    run commands from stdin, one per line
       k4draw --help | --version

Gray is 0 = black ... 255 = white (the panel shows about 16 levels). Screen: 600x800, origin top-left.

Commands:
  info                                   print screen size, stride, mode (device/sim) and font
  clear [GRAY]                           fill the screen (default 255) and do a flashing full refresh
  fill X Y W H GRAY                      filled rectangle
  rect X Y W H GRAY [T]                  rectangle outline, T px thick (default 1)
  text X Y SIZE GRAY TEXT...             TrueType text; (X,Y) = top-left of the line, SIZE in px
  ctext CX Y SIZE GRAY TEXT...           like text, centred horizontally on CX
  font PATH                              TTF/TTC used by later text commands
  image PATH [X Y]                       PNG/JPEG/BMP/GIF/PGM, converted to gray, alpha blended
  export PATH.png [--panel]              save the screen as a gray PNG (--panel: quantize to 16 levels)
  refresh [partial|full|slow|fast] [X Y W H]   refresh the panel only (slow = always flashes)

Options:
  -n   don't refresh the panel (change memory only)
  -F   refresh with a flashing full update instead of a partial one
Without -n, each command refreshes what it drew; in stdin mode one refresh covers everything at the end.

Environment:
  K4DRAW_FB=FILE    simulate: draw into FILE (raw 600x800 screen, created white) instead of /dev/fb0.
                   Works on any computer; use export to look at it.
  K4DRAW_FONT=PATH  default font (device: /usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf;
                   sim: a system sans font if found)
  K4DRAW_DEBUG=1    print refresh timings to stderr

Exit codes: 0 ok, 1 error (message on stderr), 2 usage.
```

## k4keys

```
usage: k4keys [-1] [-g] [-t SECONDS]
       k4keys --help | --version

Read the Kindle 4 NT buttons from evdev (/dev/input/event0-2).

Output, one line per key event:  NAME down|up|repeat DEV:CODE MS
  e.g. 'rnext down 0:191 1234'  (MS = milliseconds since start; NAME 'unknown' for other codes)
Names: home menu back kbd lprev lnext rprev rnext up down left right select

Options:
  -1          wait for one key press, print just its name, exit 0
  -g          grab the devices so Amazon's UI doesn't see the keys while k4keys runs
  -t SECONDS  give up after SECONDS (exit 1)

The power button is not an input device on the K4 (it goes to powerd).
Exit codes: 0 ok, 1 timeout or error, 2 usage.
```

## k4fetch

```
usage: k4fetch [options] URL
       k4fetch --help | --version

HTTP/HTTPS client with its own TLS 1.2 (BearSSL) and a small built-in set of root CAs.
HTTP/1.1, SNI, up to 5 redirects, chunked and Content-Length bodies, no compression, IPv4 only.
Needs a correct clock to validate certificates.

Options:
  -o FILE   write the body to FILE (default stdout)
  -t SECS   connect / per-read timeout (default 20)
  -H HDR    extra request header, e.g. -H 'Accept: application/json' (repeatable)
  -X METH   request method (default GET, or POST with -d)
  -d DATA   request body ("@file" reads it from a file)
  -i        include the response status line and headers in the output
  -k        don't verify the certificate (debug only; can't bypass an expired one)
  -v        verbose: timings, TLS version/cipher and redirects on stderr

Exit codes: 0 = 2xx, 1 = usage, 2 = DNS, 3 = connect/timeout/socket, 4 = TLS/certificate,
            5 = HTTP status not 2xx (body still written), 6 = bad response,
            7 = local file error, 8 = too many redirects
```

## k4press

```
Inject a key press into a Kindle input device by writing raw input_event structs.
usage: k4press <key> [hold_ms]   key = name (see below) or <dev>:<code>
32-bit ARM input_event: timeval(8) + type(u16) + code(u16) + value(s32), little-endian.
```

## k4wait

```
Wait until the e-ink framebuffer stops changing.
usage: k4wait [-c] [stable_reads=3] [interval_ms=250] [timeout_ms=8000]
  -c  first wait (up to 2s) for the screen to change - use right after a key press,
      otherwise the old, still-stable screen ends the wait before the UI reacts.
Prints elapsed ms. Exit 0 = stable, 1 = timed out.
```

## k4app

```
Hand the screen to our own code, or give it back to Amazon's UI (the Java "framework").
  k4app on      stop the framework (screen + keys are ours), clear the screen
  k4app off     restart the framework (normal Kindle UI back), even when the home screen holds it back at boot
  k4app status
Safety: rebooting always brings the framework back (nothing here is persistent).
```

## k4home

```
Home screen: a small launcher that replaces Amazon's UI at boot (install.sh --home) and keeps a way back to it.
  k4home             take the screen (stops Amazon's UI if it is running) and run the menu until reboot
  k4home --draw [N]  draw once with item N (0-based) highlighted, no keys; for screenshots and tools/sim
Keys: 5-way or page keys move (partial refresh of the two cells only), Select opens (full flash on every
screen change, which is also what clears ghosting). Home redraws. Inside the Reader, hold the Keyboard key
for about 1.5 s to come back here (Amazon's UI gets the key too, so its keyboard may flash up first).
Status bar: time, cpu % and ram % used, Wi-Fi, battery.
Items: Reader (Amazon's stock UI, started with the time zone from install.sh --tz) and About (k4about).
```

## k4about

```
neofetch-style "about this Kindle" card: model, firmware, kernel, memory, storage, battery, kindle4ever version
  k4about          take over the screen, show the card, return to Amazon's UI on any button press
  k4about --draw   just draw it (no app mode, no waiting), e.g. for screenshots
Nothing personal is shown (no serial, MAC, IP or Wi-Fi name), so it's safe to photograph.
```

## k4welcome

```
Welcome screen: the logo, the devkit name, and the device's three dates as running counters.
  k4welcome [--hold]   draw it; --hold takes over the screen until a button is pressed
```

## k4logo

```
Print k4draw commands for the devkit logo: a Kindle 4 drawn from rectangles.
  k4logo [X] [Y] [SCALE] [name]   top-left corner (default 0 0), size (1 = 150x210 px);
                                  "name" adds the kindle4ever wordmark under the device (+34 px)
Optional: K4LOGO_BODY (body gray, default 0 = black), K4LOGO_SIDE ("INSET WIDTH GRAY MODE" page-turn buttons, "" = none)
  e.g.  k4logo 225 80 1 | k4draw -
```

## k4logs

```
Show or clean the Kindle's logs. The stock system rotates /var/log (tmpfs) into /var/local/log (32 MB flash partition) every 15 min.
  k4logs                 sizes of the log areas and the oldest/newest archive
  k4logs clean [DAYS]    delete rotated archives in /var/local/log older than DAYS (default 30); keeps the live logs and tinyrot's counters
  k4logs tail [N]        last N lines of the live system log (default 30), without lipc chatter
Never deletes /var/log/messages, the *_oldest/*_youngest counters or anything outside /var/local/log and /mnt/us/system/logs.
```
