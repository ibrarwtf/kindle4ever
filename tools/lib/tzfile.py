#!/usr/bin/env python3
"""Produce a TZif zoneinfo file for the Kindle (it ships none) plus the matching POSIX TZ string.
   tzfile.py ZONE OUT_FILE      ZONE = IANA name (Asia/Kolkata) or a fixed-offset POSIX string (IST-5:30)
Prints the POSIX TZ string for /etc/TZ on stdout. IANA names need zoneinfo on this computer
(system tzdata, or `pip install tzdata`); fixed-offset strings are generated here with no data."""
import re, struct, sys

def iana_file(zone):
    import zoneinfo
    paths = list(zoneinfo.TZPATH)
    try:
        import tzdata, os
        paths.append(os.path.join(os.path.dirname(tzdata.__file__), "zoneinfo"))
    except ImportError:
        pass
    for p in paths:
        f = os.path.join(p, *zone.split("/"))
        if os.path.isfile(f):
            return open(f, "rb").read()
    return None

def fixed_offset(tz):
    # POSIX: NAME[+-]H[:MM]  (sign is inverted: IST-5:30 means UTC+5:30)
    m = re.fullmatch(r"([A-Za-z]{3,})([+-]?)(\d{1,2})(?::(\d{2}))?", tz)
    if not m:
        return None
    name, sign, h, mm = m.group(1), m.group(2), int(m.group(3)), int(m.group(4) or 0)
    off = (h * 3600 + mm * 60) * (1 if sign == "-" else -1)
    abbr = name.encode() + b"\0"
    def block(ver):
        counts = struct.pack(">6l", 0, 0, 1, 0, 1, len(abbr))  # isutc, isstd, leap, time, type, charcnt
        body = struct.pack(">lBB", off, 0, 0) + abbr  # one ttinfo (utoff, isdst, abbrind) + abbrs
        return b"TZif" + ver + b"\0" * 15 + counts + body
    return block(b"\0") + block(b"2") + b"\n" + tz.encode() + b"\n"

def posix_string(data):
    tail = data.rstrip(b"\n").rsplit(b"\n", 1)
    return tail[-1].decode() if len(tail) == 2 else ""

zone, out = sys.argv[1], sys.argv[2]
import os
data = fixed_offset(zone) or iana_file(zone)
if not data:
    sys.exit(f"tzfile: no zoneinfo for {zone!r} on this computer (pip install tzdata) and it is not a fixed-offset TZ string")
open(out, "wb").write(data)
print(posix_string(data) or zone)
