#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
state="$root/.build/debug-state"
label=""
pid=""
out=""

usage() {
  echo "usage: scripts/capture.sh <label> [--pid <pid>] [--out <dir>] [--state-dir <dir>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pid|--out|--state-dir)
      [ $# -ge 2 ] || usage
      case "$1" in
        --pid) pid=$2 ;;
        --out) out=$2 ;;
        --state-dir) state=$2 ;;
      esac
      shift
      ;;
    -*) usage ;;
    *) [ -z "$label" ] || usage; label=$1 ;;
  esac
  shift
done
[ -n "$label" ] || usage
[ ! -d "$state" ] || state=$(cd "$state" && pwd -P)
[[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "capture: use letters, digits, dot, dash or underscore in the label" >&2; exit 2; }

if [ -z "$pid" ]; then
  pid=$(plutil -extract pid raw -o - "$state/run.json" 2>/dev/null) \
    || { echo "capture: give --pid, or run scripts/run-debug.sh first" >&2; exit 2; }
fi
kill -0 "$pid" 2>/dev/null || { echo "capture: pid $pid is not running" >&2; exit 1; }

out=${out:-"$state/captures"}
mkdir -p "$out" || exit 1
out=$(cd "$out" && pwd -P)

windows=$(osascript -l JavaScript "$root/scripts/lib/windows.js" "$pid") \
  || { echo "capture: cannot list the windows of pid $pid" >&2; exit 1; }
visible=$(printf '%s\n' "$windows" | awk 'NF == 6 && $5 > 1 && $6 > 1')
region=$(printf '%s\n' "$visible" | awk '
  NF == 6 {
    if (!seen || $3 < left) left = $3
    if (!seen || $4 < top) top = $4
    if (!seen || $3 + $5 > right) right = $3 + $5
    if (!seen || $4 + $6 > bottom) bottom = $4 + $6
    seen = 1
  }
  END { if (seen) printf "%d,%d,%d,%d", left, top, right - left, bottom - top }')
[ -n "$region" ] || { echo "capture: pid $pid has no window on screen" >&2; exit 1; }

last=$(find "$out" -maxdepth 1 -name '[0-9][0-9]-*.png' -exec basename {} \; | sort | tail -n 1)
next=1
[ -z "$last" ] || next=$(( 10#${last:0:2} + 1 ))
file="$out/$(printf '%02d' "$next")-$label.png"

if [ "$(printf '%s\n' "$visible" | wc -l)" -eq 1 ]; then
  screencapture -x -o -l "${visible%% *}" "$file" || { echo "capture: screencapture failed" >&2; exit 1; }
else
  screencapture -x -R "$region" "$file" || { echo "capture: screencapture failed" >&2; exit 1; }
fi
[ -s "$file" ] || { echo "capture: screencapture wrote nothing to $file" >&2; exit 1; }
printf '%s\n' "$file"
