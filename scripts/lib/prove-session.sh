#!/bin/bash
set -uo pipefail

[ $# -eq 5 ] || { echo "usage: prove-session.sh <side> <worktree> <state-dir> <proof> <out-dir>" >&2; exit 64; }
side=$1 worktree=$2 state=$3 proof=$4 out=$5

. "$(dirname "$0")/proof.sh"
proof_load "$proof" || { echo "prove: $proof_error" >&2; exit 64; }

scripts="$worktree/scripts"
mkdir -p -m 700 "$state" "$out/captures" || exit 3
: > "$out/checks.ndjson"

launch_arguments=()
index=0
while [ $index -lt ${#proof_kinds[@]} ]; do
  rest=${proof_args[$index]}
  case "${proof_kinds[$index]}" in
    set)
      read -r key type value <<< "$rest"
      defaults write "$state/defaults" "$key" "-$type" "$value" || exit 3
      ;;
    launch)
      read -r -a words <<< "$rest"
      launch_arguments+=("${words[@]}")
      ;;
  esac
  index=$((index + 1))
done

launched=$("$scripts/run-debug.sh" --no-build --state-dir "$state" ${launch_arguments[@]+"${launch_arguments[@]}"}) || {
  echo "prove: the $side app did not start" >&2
  exit 2
}
pid=$(jq -r '.pid // empty' <<< "$launched")
[[ "$pid" =~ ^[0-9]+$ ]] || { echo "prove: the $side app printed no pid" >&2; exit 2; }

stop() {
  "$scripts/stop-debug.sh" --state-dir "$state" "$pid" >&2
}
trap stop EXIT
trap 'exit 3' INT TERM

failed=0
index=0
while [ $index -lt ${#proof_kinds[@]} ]; do
  rest=${proof_args[$index]}
  index=$((index + 1))
  case "${proof_kinds[$((index - 1))]}" in
    run)
      read -r -a words <<< "$rest"
      "$scripts/debug.sh" --state-dir "$state" "${words[@]}" >/dev/null || { echo "prove: the $side app failed: $rest" >&2; exit 3; }
      ;;
    shot)
      "$scripts/capture.sh" --state-dir "$state" --pid "$pid" --out "$out/captures" "$rest" >/dev/null \
        || { echo "prove: the $side app could not capture $rest" >&2; exit 3; }
      ;;
    check)
      snapshot=$("$scripts/debug.sh" --state-dir "$state" state) || { echo "prove: the $side app gave no state for: $rest" >&2; exit 3; }
      printf '%s\n' "$snapshot" | jq -e "$rest" >/dev/null 2>&1
      status=$?
      case "$status" in
        0) passed=true ;;
        1) passed=false; failed=1 ;;
        *) echo "prove: jq failed on the $side state for: $rest" >&2; exit 3 ;;
      esac
      jq -cn --arg check "$rest" --argjson passed "$passed" '{check: $check, passed: $passed}' >> "$out/checks.ndjson"
      ;;
  esac
done
exit "$failed"
