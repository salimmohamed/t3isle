#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
state="$root/.build/debug-state"
timeout=40
words=()

usage() {
  echo "usage: scripts/debug.sh [--state-dir <dir>] <command> [args...]" >&2
  exit 2
}

missing() {
  echo "debug: $1" >&2
  exit 2
}

timed_out() {
  echo "debug: $1 within $timeout seconds" >&2
  exit 3
}

while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir)
      [ $# -ge 2 ] || usage
      state=$2
      shift
      ;;
    *) words+=("$1") ;;
  esac
  shift
done
[ ${#words[@]} -gt 0 ] || usage
[ ! -d "$state" ] || state=$(cd "$state" && pwd -P)

run="$state/run.json"
[ -f "$run" ] || missing "no $run, run scripts/run-debug.sh first"
app=$(jq -r '.app // empty' "$run")
log=$(jq -r '.log // empty' "$run")
pid=$(jq -r '.pid // empty' "$run")
executable="$app/Contents/MacOS/T3 Isle"
[ -x "$executable" ] || missing "no app at $app"
[ -f "$log" ] || missing "no event log at $log"

copies=$(ps -axww -o pid=,args= | awk -v exe="$executable" '
  {
    copy = $1
    sub(/^ *[0-9]+ /, "")
    if ($0 == exe || index($0, exe " ") == 1) print copy
  }')
[[ "$pid" =~ ^[0-9]+$ ]] || missing "no pid in $run, run scripts/run-debug.sh first"
printf '%s\n' "$copies" | grep -qx "$pid" \
  || missing "pid $pid from $run is not running, start it with scripts/run-debug.sh"
[ "$(printf '%s\n' "$copies" | wc -l)" -eq 1 ] \
  || missing "$(printf '%s\n' "$copies" | wc -l | tr -d ' ') copies of $app are running and a URL reaches only one, stop all but pid $pid"

encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

nonce=$(uuidgen | tr 'A-Z' 'a-z')
url="t3isle-debug://$(encode "${words[0]}")"
for word in "${words[@]:1}"; do url+="/$(encode "$word")"; done
url+="?n=$nonce"

offset=$(stat -f %z "$log")
source_before=""
[ "$offset" -eq 0 ] \
  || source_before=$(head -c "$offset" "$log" | jq -rR 'fromjson? | select(.event == "app.launched") | .attributes.source' | tail -n 1)
deadline=$((SECONDS + timeout))
open -g -a "$app" "$url" || missing "open could not send $url to $app"

event=""
wait_for() {
  local filter=$1 what=$2
  shift 2
  while :; do
    [ "$(stat -f %z "$log")" -ge "$offset" ] || offset=0
    event=$(tail -c +"$((offset + 1))" "$log" | jq -cR "$@" "fromjson? | select($filter)" | head -n 1)
    [ -z "$event" ] || return 0
    [ "$SECONDS" -lt "$deadline" ] || timed_out "$what"
    sleep 0.1
  done
}

wait_for '(.event == "command.ran" or .event == "command.failed") and ((.attributes.input // "") | contains($nonce))' \
  "the app logged no result for $url" --arg nonce "$nonce"
if [ "$(jq -r .event <<< "$event")" = "command.failed" ]; then
  echo "debug: $(jq -r .attributes.message <<< "$event")" >&2
  exit 1
fi
ran=$event
command=$(jq -r .attributes.command <<< "$ran")

case "$command" in
  "replay off") ;;
  "replay "*)
    scenario=${command#replay }
    wait_for '.event == "replay.finished" and .attributes.scenario == $scenario' \
      "replay $scenario did not finish" --arg scenario "$scenario"
    ;;
  "demo "*)
    wanted=live
    [ "$command" = "demo on" ] && wanted=demo
    if [ "$source_before" != "$wanted" ]; then
      wait_for '.event == "app.launched" and .attributes.source == $source' \
        "the app did not relaunch in $wanted mode" --arg source "$wanted"
      relaunched=$(jq -r .attributes.pid <<< "$event")
      while kill -0 "$pid" 2>/dev/null; do
        [ "$SECONDS" -lt "$deadline" ] || timed_out "pid $pid did not quit after the relaunch"
        sleep 0.1
      done
      echo "debug: relaunched as pid $relaunched" >&2
    fi
    ;;
  state)
    offset=$((offset + $(tail -c +"$((offset + 1))" "$log" | grep -F -m 1 -b "$nonce" | cut -d: -f1)))
    wait_for '.event == "state.written" or .event == "state.failed"' "the app wrote no state"
    if [ "$(jq -r .event <<< "$event")" = "state.failed" ]; then
      echo "debug: $(jq -r .attributes.message <<< "$event")" >&2
      exit 1
    fi
    cat "$(jq -r .attributes.path <<< "$event")" || exit 1
    if [ "$(jq -r .attributes.settled <<< "$event")" != "true" ]; then
      echo "debug: the app wrote the state before it settled" >&2
      exit 3
    fi
    exit 0
    ;;
esac
printf '%s\n' "$ran"
