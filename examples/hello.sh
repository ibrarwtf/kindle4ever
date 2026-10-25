#!/bin/sh
# Smoke test for `tools/k4 run`: draw text on the e-ink screen with eips.
eips -c
eips 2 5 "Hello from kindle4ever"
eips 2 7 "$(uname -r) / $(cat /proc/loadavg)"
eips 2 9 "$(date)"
echo "drew on screen"
