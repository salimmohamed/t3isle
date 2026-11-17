#!/bin/bash
set -euo pipefail

minutes="${1:-10}"
file="${2:-$HOME/Library/Logs/T3 Isle Debug/events.ndjson}"

if [[ ! "$minutes" =~ ^[0-9]+$ ]]; then
  echo "Usage: scripts/debug-log.sh [minutes] [file]" >&2
  exit 64
fi

if [[ ! -f "$file" ]]; then
  echo "No event log at $file" >&2
  exit 2
fi

now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
since=$(date -u -v-"${minutes}"M +%Y-%m-%dT%H:%M:%S.000Z)
events=$(jq -cR --arg since "$since" 'fromjson? | select(.time >= $since)' "$file")

echo "Events from $since to $now"
if [[ -z "$events" ]]; then
  echo "No events in the last $minutes minutes"
  exit 0
fi

echo
echo "Counts"
jq -rs 'group_by(.event) | map([length, .[0].event]) | sort_by(-.[0], .[1]) | .[] | "  \(.[0])\t\(.[1])"' <<< "$events"

echo
echo "Failed commands"
failures=$(jq -r 'select(.event == "command.failed") | "  \(.time) \(.attributes.input): \(.attributes.message)"' <<< "$events")
echo "${failures:-  none}"

echo
echo "Last 20 events"
jq -rs '.[-20:][] | "  \(.time) \(.event)\([.attributes | to_entries[] | " \(.key)=\(.value)"] | add // "")"' <<< "$events"
