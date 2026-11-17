#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
state="$root/.build/debug-state"
pid=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      [ $# -ge 2 ] || { echo "stop-debug: --state-dir needs a path" >&2; exit 2; }
      state=$2
      shift
      ;;
    *) pid=$1 ;;
  esac
  shift
done

if [ -z "$pid" ]; then
  pid=$(plutil -extract pid raw -o - "$state/run.json" 2>/dev/null) \
    || { echo "stop-debug: give a pid, or run scripts/run-debug.sh first" >&2; exit 2; }
fi
[[ "$pid" =~ ^[0-9]+$ ]] || { echo "stop-debug: $pid is not a pid" >&2; exit 2; }

command=$(ps -ww -o args= -p "$pid" 2>/dev/null) || { echo "stop-debug: pid $pid is not running" >&2; exit 0; }
case "$command" in
  "/Applications/"*) echo "stop-debug: pid $pid is an installed app, not a Debug build: $command" >&2; exit 2 ;;
  /*"/T3 Isle.app/Contents/MacOS/T3 Isle" | /*"/T3 Isle.app/Contents/MacOS/T3 Isle "*) ;;
  *) echo "stop-debug: pid $pid is not T3 Isle: $command" >&2; exit 2 ;;
esac

children=$(pgrep -P "$pid")
child_commands=()
for child in $children; do
  child_commands+=("$child $(ps -ww -o args= -p "$child")")
done
kill -TERM "$pid" 2>/dev/null
for _ in $(seq 1 80); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.25
done
if kill -0 "$pid" 2>/dev/null; then
  echo "stop-debug: pid $pid did not quit within 20 seconds" >&2
  exit 1
fi
for entry in ${child_commands[@]+"${child_commands[@]}"}; do
  child=${entry%% *}
  [ "$child $(ps -ww -o args= -p "$child" 2>/dev/null)" = "$entry" ] && kill -TERM "$child" 2>/dev/null
done
echo "stop-debug: stopped $pid" >&2
