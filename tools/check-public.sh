#!/bin/sh
# Check the repo for personal or device-specific data before publishing.
#   tools/check-public.sh            scan files git would publish (or all files outside git)
#   tools/check-public.sh --hook     same; meant for .git/hooks/pre-push (see docs/setup.md)
#
# Two layers:
#  1. Generic patterns (also run in CI): Kindle serials, MAC addresses, private IPv4 addresses,
#     private keys, SSH public keys, email addresses, and files that shouldn't be in the repo
#     (disk images, keys, archives, update .bins). Known-safe values: tools/leakcheck-allow.txt.
#  2. Your exact values (local only): one literal string per line in $K4_LEAKLIST (serial, MAC,
#     IP prefix, Wi-Fi name, key fingerprint, email...). Keep that file OUTSIDE the repo.
# Also runs gitleaks if installed. Exit 1 on any finding.
cd "$(dirname "$0")/.." || exit 1
. tools/lib/env.sh 2>/dev/null

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  files=$( { git ls-files; git ls-files --others --exclude-standard; } | sort -u)
else
  files=$(find . -type f -not -path './.git/*' -not -path './build/*' -not -path './toolchain/*' -not -path './vendor/*' | sed 's#^\./##')
fi
# third_party is upstream code (licenses with emails, test vectors); scanned only for layer 2.
scan=$(printf '%s\n' "$files" | grep -v -e '^third_party/' -e '^tools/leakcheck-allow.txt$' -e '^tools/check-public.sh$')
allow=tools/leakcheck-allow.txt
fail=0

report() { echo "LEAK? $1"; fail=1; }

check() {  # check <label> <extended regex>
  hits=$(printf '%s\n' "$scan" | tr '\n' '\0' | xargs -0 grep -nIEo "$2" 2>/dev/null | grep -v -F -f "$allow")
  [ -n "$hits" ] && printf '%s\n' "$hits" | while IFS= read -r h; do report "$1: $h"; done && fail=1
  [ -z "$hits" ]
}

check "Kindle serial"   '\b(B0|90)[0-9A-F]{2}[0-9A-Z]{12}\b' || fail=1
check "MAC address"     '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b' || fail=1
check "private IPv4"    '\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b' || fail=1
check "private key"     'BEGIN ([A-Z]+ )?PRIVATE KEY' || fail=1
check "SSH public key"  'ssh-(rsa|ed25519|dss) AAAA[0-9A-Za-z+/]{20,}' || fail=1
check "email address"   '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[A-Za-z]{2,}' || fail=1

bad=$(printf '%s\n' "$files" | grep -E '\.(img|bin|zip|tar\.gz|tgz|key|p12|pfx)$|(^|/)id_(rsa|ed25519)|(^|/)k4\.env$|known_hosts$' | grep -v -F -f "$allow")
[ -n "$bad" ] && { printf '%s\n' "$bad" | while IFS= read -r f; do echo "LEAK? file that shouldn't be published: $f"; done; fail=1; }
pems=$(printf '%s\n' "$files" | grep '\.pem$' | grep -v '^src/k4fetch/roots/')
[ -n "$pems" ] && { printf '%s\n' "$pems" | while IFS= read -r f; do echo "LEAK? .pem outside src/k4fetch/roots: $f"; done; fail=1; }

if [ -n "${K4_LEAKLIST:-}" ] && [ -f "$K4_LEAKLIST" ]; then
  pats=$(mktemp); tr -d '\r' < "$K4_LEAKLIST" | grep -v -e '^#' -e '^$' > "$pats"
  hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -nIF -f "$pats" 2>/dev/null)
  rm -f "$pats"
  [ -n "$hits" ] && { printf '%s\n' "$hits" | while IFS= read -r h; do echo "LEAK! your private value: $h"; done; fail=1; }
  echo "checked $(grep -cv -e '^#' -e '^$' "$K4_LEAKLIST") private values from \$K4_LEAKLIST"
else
  echo "note: K4_LEAKLIST not set - only generic patterns checked"
fi

if command -v gitleaks >/dev/null 2>&1; then
  # scan a copy of just the publishable files (not build/, toolchain/, ...)
  stage=$(mktemp -d)
  printf '%s\n' "$files" | tar -cf - -T - 2>/dev/null | tar -xf - -C "$stage"
  if ! gitleaks detect --no-git --no-banner --redact -s "$stage" >/dev/null 2>&1; then
    echo "LEAK? gitleaks found something:"
    gitleaks detect --no-git --no-banner --redact -s "$stage" -v 2>&1 | grep -E 'RuleID|File:' | sed "s#$stage/##"
    fail=1
  fi
  rm -rf "$stage"
fi

[ $fail = 0 ] && echo "check-public: clean" || echo "check-public: FAILED"
exit $fail
