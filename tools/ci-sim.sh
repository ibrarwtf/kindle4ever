#!/bin/sh
# Simulator-based checks (CI and local, Linux only). Needs: busybox, qemu-arm (qemu-user), the ARM + host builds in build/,
# fonts-dejavu-core or vendor/ DejaVu for text. Everything runs against the simulated screen; no Kindle, no private files.
#   tools/ci-sim.sh            run all checks, exit 1 on the first failure
set -e
cd "$(dirname "$0")/.."
BB=$(command -v busybox) || { echo "ci-sim: busybox not found"; exit 1; }
QEMU=$(command -v qemu-arm-static || command -v qemu-arm) || { echo "ci-sim: qemu-arm not found"; exit 1; }
SIM=build/ci-sim; rm -rf "$SIM"; mkdir -p "$SIM"
export K4_SIM="$SIM" K4DRAW_FB="$SIM/screen.raw" K4DRAW_TRACE="$SIM/trace.txt" LC_ALL=C TZ=UTC
# a monospace font with box-drawing glyphs, and a sans for everything else
MONO=$(ls vendor/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSansMono.ttf /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf 2>/dev/null | head -1)
SANS=$(ls vendor/dejavu/dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf 2>/dev/null | head -1)
[ -n "$MONO" ] && [ -n "$SANS" ] || { echo "ci-sim: DejaVu fonts not found (apt install fonts-dejavu-core or tools/fetch-vendor.sh)"; exit 1; }
mkdir -p "$SIM/fonts"; cp "$SANS" "$SIM/fonts/Helvetica_LT_65_Medium.ttf"; cp "$SANS" "$SIM/fonts/Helvetica_LT_75_Bold.ttf"
export K4DRAW_FONTDIR="$PWD/$SIM/fonts"
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; exit 1; }

echo "== 1. device scripts parse under busybox sh, awk programs under busybox awk"
for f in device/bin/* device/kindle4ever/boot.sh apps/*/*.sh; do "$BB" sh -n "$f" || fail "busybox sh -n $f"; done
for f in apps/*/*.awk; do "$BB" awk -f "$f" /dev/null >/dev/null 2>&1 || fail "busybox awk parse $f"; done
ok "busybox sh/awk parse"

echo "== 2. app metadata"
for a in apps/*/; do
  grep -q '^# name: ' "$a/app.sh" || fail "$a: no '# name:' line"
  grep -q '^# version: ' "$a/app.sh" || fail "$a: no '# version:' line"
  [ -f "$a/README.md" ] || fail "$a: no README.md"
done
! git ls-files | grep -i -q 'Helvetica_LT\|Caecilia\|KindleBlackbox' || fail "a Kindle font file is tracked"
ok "apps have name, version, README; no licensed fonts tracked"

echo "== 3. k4home draws under busybox sh with the simulator stubs"
STAGE=$SIM/stage; mkdir -p "$STAGE/bin" "$STAGE/apps"
cp build/host/k4draw "$STAGE/bin/"; cp device/bin/* "$STAGE/bin/"; cp tools/simbin/* "$STAGE/bin/"; chmod +x "$STAGE/bin/"*
for a in apps/*/; do n=$(basename "$a"); mkdir -p "$STAGE/apps/$n"; cp -r "$a"* "$STAGE/apps/$n/"; cp "$MONO" "$STAGE/apps/$n/DejaVuSansMono.ttf"; done
export PATH="$PWD/$STAGE/bin:$PATH"
# k4home expects /mnt/us/kindle4ever/apps: point it at the stage with a sed'ed copy (the real path needs root to create)
# device scripts hard-code the Kindle's paths; CI has no /mnt/us, so point their PATH and app folder at the stage
sed "s|^APPS=/mnt/us/kindle4ever/apps|APPS=$PWD/$STAGE/apps|; s|^export PATH=/mnt/us/kindle4ever/bin:|export PATH=$PWD/$STAGE/bin:|" device/bin/k4home > "$SIM/k4home"
grep -q "^export PATH=$PWD" "$SIM/k4home" || fail "could not relocate k4home's PATH for the stage"
rm -f "$K4DRAW_TRACE"
"$BB" sh "$SIM/k4home" --draw 0 >/dev/null
k4draw export "$SIM/home.png" --panel >/dev/null
black=$("$BB" od -An -v -tu1 "$K4DRAW_FB" | tr -s ' ' '\n' | grep -c '^255$' || true)
[ "$black" -gt 2000 ] || fail "k4home screen looks blank ($black black pixels)"
ok "k4home drew ($black black pixels)"

echo "== 4. livestation end to end with the fixture (host k4draw, landscape)"
export LIVESTATION_FIXTURE="$PWD/apps/livestation/test/sample-mas.html"
cat > "$STAGE/apps/livestation/station.conf" <<'EOF'
CODE=MAS
NAME="MGR CHENNAI CENTRAL"
LEFT="ARAKKONAM / BENGALURU"
RIGHT="GUDUR / VIJAYAWADA"
RIGHT_SIDE="GDR BZA VSKP HWH NDLS SC HYB"
PLATFORMS="1 2 3"
EOF
: > "$K4DRAW_TRACE"
# app.sh writes to /var/run/<app>; redirect with a sed'ed copy as well (no root in CI)
sed "s|^T=/var/run/livestation|T=$PWD/$SIM/run|; s|^A=\$(dirname \"\$0\")|A=$PWD/$STAGE/apps/livestation|; s|^export PATH=/mnt/us/kindle4ever/bin:|export PATH=$PWD/$STAGE/bin:|" "$STAGE/apps/livestation/app.sh" > "$SIM/app.sh"
grep -q "^export PATH=$PWD" "$SIM/app.sh" || fail "could not relocate app.sh's PATH for the stage"
grep -q "^A=$PWD" "$SIM/app.sh" || fail "could not relocate app.sh's A= for the stage"
"$BB" sh "$SIM/app.sh" --once | tee "$SIM/once.txt"
grep -q 'rows 8' "$SIM/once.txt" || fail "livestation --once did not parse 8 rows"
[ "$(wc -l < "$SIM/run/board.txt")" -eq 23 ] || fail "board is not 23 lines"
grep -q 'fx=3 0 0 800 600' "$K4DRAW_TRACE" || fail "no full-screen landscape flash in the trace"
K4DRAW_ROTATE=90 k4draw export "$SIM/livestation-host.png" >/dev/null
ok "livestation drew the fixture board in landscape"

echo "== 5. ARM k4draw (qemu) renders the same pixels as the host k4draw"
awk -v mono="$PWD/$STAGE/apps/livestation/DejaVuSansMono.ttf" -v title="MGR CHENNAI CENTRAL STATION" -v left="ARAKKONAM / BENGALURU" \
    -v right="GUDUR / VIJAYAWADA" -f apps/livestation/render.awk "$SIM/run/board.txt" > "$SIM/cmds.txt"
rm -f "$SIM/host.raw" "$SIM/arm.raw"
K4DRAW_FB="$SIM/host.raw" K4DRAW_ROTATE=90 k4draw - < "$SIM/cmds.txt"
K4DRAW_FB="$SIM/arm.raw"  K4DRAW_ROTATE=90 "$QEMU" build/k4draw - < "$SIM/cmds.txt"
cmp "$SIM/host.raw" "$SIM/arm.raw" || fail "ARM and host k4draw rendered different pixels"
ok "ARM and host renders are identical ($(wc -c < "$SIM/arm.raw") bytes)"
echo "all simulator checks passed"
