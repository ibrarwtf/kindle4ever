#!/bin/sh
# Status: written for Linux/macOS but untested there so far.
# Get the Kindle back on Wi-Fi and find its IP (Linux / macOS; on Windows use find-kindle.ps1).
# Each try:
#   - if the Kindle drive is mounted (USB Drive Mode = Wi-Fi off), eject it;
#   - ping-sweep the subnet and look up the Kindle's MAC in the ARP/neighbour table;
#   - succeed only when TCP port 22 answers.
# Settings: K4_MAC, K4_SUBNET (e.g. 192.168.1). The IP found is written to the k4.env file
# in use (if any) as K4_HOST, and printed.
. "$(dirname "$0")/lib/env.sh"
k4_need K4_MAC K4_SUBNET
MAC=$(printf '%s' "$K4_MAC" | tr 'A-F-' 'a-f:')
TRIES=${1:-30}

eject_kindle() {
  case "$(uname)" in
    Darwin) [ -d /Volumes/Kindle ] && { echo "ejecting /Volumes/Kindle"; diskutil eject /Volumes/Kindle >/dev/null; } ;;
    *) dev=$(lsblk -rno NAME,LABEL 2>/dev/null | awk '$2=="Kindle"{print "/dev/"$1; exit}')
       [ -n "$dev" ] && grep -q "^$dev " /proc/mounts && { echo "ejecting $dev"; udisksctl unmount -b "$dev" >/dev/null && udisksctl power-off -b "$dev" >/dev/null; } ;;
  esac
}

lookup_ip() {  # print the IP whose MAC matches, from the neighbour table
  # macOS arp drops leading zeros (0a -> a), so compare MACs with each octet as a number
  { ip neigh 2>/dev/null || arp -an 2>/dev/null; } | tr 'A-F()' 'a-f  ' | awk -v want="$MAC" '
    function hex(h,  i, v) { v = 0; for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return v }
    function norm(m,  p, n, i, s) { n = split(m, p, ":"); s = ""; for (i = 1; i <= n; i++) s = s ":" hex(p[i]); return s }
    BEGIN { w = norm(want) }
    { ip = ""; mac = ""
      for (i = 1; i <= NF; i++) { if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) ip = $i; if ($i ~ /^[0-9a-f]+(:[0-9a-f]+){5}$/) mac = $i }
      if (ip != "" && mac != "" && norm(mac) == w) { print ip; exit } }'
}

port_open() { nc -z -w 2 "$1" 22 2>/dev/null || bash -c "exec 3<>/dev/tcp/$1/22" 2>/dev/null; }

i=0
while [ $i -lt "$TRIES" ]; do
  i=$((i + 1))
  eject_kindle
  for n in $(seq 1 254); do ping -c 1 -W 1 "$K4_SUBNET.$n" >/dev/null 2>&1 & done; wait
  ip=$(lookup_ip)
  if [ -n "$ip" ] && port_open "$ip"; then
    if [ -n "${K4_ENV_FILE:-}" ]; then
      if grep -q '^K4_HOST=' "$K4_ENV_FILE"; then sed -i.bak "s/^K4_HOST=.*/K4_HOST=$ip/" "$K4_ENV_FILE" && rm -f "$K4_ENV_FILE.bak"
      else echo "K4_HOST=$ip" >> "$K4_ENV_FILE"; fi
    fi
    echo "Kindle at $ip (ssh port open)"; exit 0
  fi
  sleep 5
done
echo "Kindle not found (asleep? Wi-Fi off? not joined to the network?)"; exit 1
