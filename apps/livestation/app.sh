#!/bin/sh
# name: Live station
# version: 0.1.0
# Indian Railways live platform board for one station, fully on the Kindle: NTES Live Station over k4fetch,
# busybox awk for parsing and layout, k4draw in landscape (K4DRAW_ROTATE=90, keypad on the right).
# Config: station.conf next to this script (copy station.conf.example). Select = refresh now, Back/Home = exit.
#   app.sh [--once]      --once: one fetch + draw with timings, then exit
# Offline / simulator: LIVESTATION_FIXTURE=/path/page.html uses that saved NTES page instead of fetching.
export PATH=/mnt/us/kindle4ever/bin:/usr/sbin:/sbin:/usr/bin:/bin
[ -f /etc/TZ ] && { TZ=$(cat /etc/TZ); export TZ; }
A=$(dirname "$0")
T=/var/run/livestation; mkdir -p $T
[ -f "$A/station.conf" ] || { k4draw clear >/dev/null; k4draw text 20 300 22 0 "livestation: no station.conf (see station.conf.example)"; sleep 4; exit 1; }
. "$A/station.conf"
REFRESH=${REFRESH:-300}
B=https://enquiry.indianrail.gov.in/mntes
UA="Mozilla/5.0 (Linux; Android 12)"
export K4DRAW_ROTATE=90

urlenc() { printf '%s' "$1" | sed 's/ /+/g'; }

fetch() {   # -> $T/page.html ; NTES wants a session cookie and a fresh CSRF field for every query
  if [ -n "$LIVESTATION_FIXTURE" ]; then cp "$LIVESTATION_FIXTURE" $T/page.html; return; fi
  k4fetch -t 15 -i -H "User-Agent: $UA" -o $T/h0 "$B/" || return 1
  ck=$(grep -i '^Set-Cookie:' $T/h0 | sed 's/^[Ss]et-[Cc]ookie: *//; s/;.*//' | tr '\n' ';')
  k4fetch -t 15 -H "User-Agent: $UA" -H "Cookie: $ck" -H "Referer: $B/" -o $T/tok "$B/GetCSRFToken?t=0" || return 1
  nm=$(sed "s/.*name='\([^']*\)'.*/\1/" $T/tok); vl=$(sed "s/.*value='\([^']*\)'.*/\1/" $T/tok)
  k4fetch -t 20 -H "User-Agent: $UA" -H "Cookie: $ck" -H "Referer: $B/" -H "Content-Type: application/x-www-form-urlencoded" \
    -d "lan=en&jFromStationInput=$(urlenc "$CODE - $NAME")&jToStationInput=&nHr=${HOURS:-8}&appLang=en&jStnName=&jStation=&$nm=$vl" \
    -o $T/page.html "$B/q?opt=LiveStation&subOpt=show"
}

draw() {   # page.html -> rows -> board text -> k4draw
  awk -f "$A/ntes.awk" $T/page.html > $T/rows.txt
  [ -s $T/rows.txt ] || return 1
  awk -v now="$(date +%H:%M)" -v date="$(date '+%a %d %b' | tr 'a-z' 'A-Z')" -v code="$CODE" -v name="$NAME" \
      -v llabel="$LEFT" -v rlabel="$RIGHT" -v rightside="$RIGHT_SIDE" -v platforms="${PLATFORMS:-1 2 3}" -f "$A/board.awk" $T/rows.txt > $T/board.txt
  awk -v mono="$A/DejaVuSansMono.ttf" -v title="$(printf '%s STATION' "$NAME" | tr 'a-z' 'A-Z')" -v left="$LEFT" -v right="$RIGHT" \
      -f "$A/render.awk" $T/board.txt | k4draw -a -
}

msg() { k4draw text 20 560 16 0 "$*"; }

if [ "$1" = "--once" ]; then
  t0=$(cut -d' ' -f1 /proc/uptime); fetch; t1=$(cut -d' ' -f1 /proc/uptime); draw; t2=$(cut -d' ' -f1 /proc/uptime)
  echo "fetch $(echo "$t1 $t0" | awk '{print $1-$2}')s  draw $(echo "$t2 $t1" | awk '{print $1-$2}')s  page $(wc -c < $T/page.html) B  rows $(wc -l < $T/rows.txt)"
  exit 0
fi

[ "$(k4app status)" = "framework running" ] && k4app on >/dev/null
k4draw clear >/dev/null
k4draw text 20 280 24 0 "$CODE: fetching NTES live station..."
while :; do
  if fetch && draw; then :; else msg "NTES unreachable, retry in $REFRESH s"; fi
  key=$(k4keys -1 -t "$REFRESH")
  case "$key" in back|home) break ;; esac
done
