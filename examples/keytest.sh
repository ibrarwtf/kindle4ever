#!/bin/sh
# Interactive button test: app mode, list all buttons, tick each off as it's physically pressed.
# Ends when all are pressed or after 180 s, then gives the screen back to the framework.
# Log: /tmp/keytest.log
export PATH=/mnt/us/kindle4ever/bin:/usr/sbin:/sbin:/usr/bin:/bin
KEYS="home menu back kbd lprev lnext rprev rnext up down left right select"
LOG=/tmp/keytest.log
: > $LOG
k4app on >/dev/null
row() { # index -> y
  echo $((150 + $1 * 42))
}
{
  echo "text 30 30 40 0 Button test"
  echo "text 30 85 22 0 Press every button once (180 s max)."
  i=0
  for k in $KEYS; do echo "text 80 $(row $i) 30 0 $k"; i=$((i+1)); done
} | k4draw -
left=$KEYS
k4keys -t 180 | while read name state dev ms; do
  echo "$name $state $dev $ms" >> $LOG
  [ "$state" = down ] || continue
  i=0
  for k in $KEYS; do
    if [ "$k" = "$name" ]; then
      y=$(row $i)
      printf "fill 30 %d 40 34 0\ntext 300 %d 30 0 OK %s\n" $y $y "$dev" | k4draw -
    fi
    i=$((i+1))
  done
  left=$(echo " $left " | sed "s/ $name / /")
  left=$(echo $left)
  if [ -z "$left" ]; then
    echo "ALL DONE" >> $LOG
    k4draw text 30 720 34 0 "All buttons work!"
    sleep 4
    killall k4keys  # else the pipeline waits for k4keys to time out
    break
  fi
done
# (the loop runs in a pipeline subshell, so $left is not visible here)
pkill k4keys 2>/dev/null
k4app off >/dev/null
echo END >> $LOG
