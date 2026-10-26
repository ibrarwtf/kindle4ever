#!/bin/sh
# Home-screen icon: a small train (engine + two coaches on a track), as k4draw commands.  icon.sh CX CY
cx=$1; cy=$2
# coaches
echo "rect $((cx - 56)) $((cy - 22)) 40 30 0 3"; echo "rect $((cx - 12)) $((cy - 22)) 40 30 0 3"
echo "fill $((cx - 48)) $((cy - 14)) 8 8 0";  echo "fill $((cx - 32)) $((cy - 14)) 8 8 0"
echo "fill $((cx - 4)) $((cy - 14)) 8 8 0";   echo "fill $((cx + 12)) $((cy - 14)) 8 8 0"
# engine: cab + nose + chimney + smoke
echo "rect $((cx + 32)) $((cy - 22)) 22 30 0 3"; echo "fill $((cx + 52)) $((cy - 8)) 10 16 0"
echo "fill $((cx + 38)) $((cy - 32)) 6 10 0"; echo "fill $((cx + 34)) $((cy - 40)) 14 3 120"; echo "fill $((cx + 38)) $((cy - 46)) 10 3 160"
# couplers, wheels, track
echo "fill $((cx - 16)) $((cy - 9)) 4 4 0"; echo "fill $((cx + 28)) $((cy - 9)) 4 4 0"
for wx in -46 -30 -2 14 36 50; do echo "fill $((cx + wx)) $((cy + 8)) 6 6 0"; done
echo "fill $((cx - 60)) $((cy + 16)) 124 2 0"; echo "fill $((cx - 60)) $((cy + 20)) 124 2 0"
