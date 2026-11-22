#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
base_ref=origin/main
head_ref=HEAD
out="$root/.build/prove-out"
proof=""

usage() {
  echo "usage: scripts/prove.sh [--base <ref>] [--head <ref>] [--out <dir>] <proof file or name>" >&2
  exit 64
}

die() {
  echo "prove: $1" >&2
  exit "${2:-64}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base | --head | --out)
      [ $# -ge 2 ] || usage
      case "$1" in
        --base) base_ref=$2 ;;
        --head) head_ref=$2 ;;
        --out) out=$2 ;;
      esac
      shift
      ;;
    -*) usage ;;
    *) [ -z "$proof" ] || usage; proof=$1 ;;
  esac
  shift
done
[ -n "$proof" ] || usage

. "$root/scripts/lib/proof.sh"
command -v jq >/dev/null 2>&1 || die "jq is missing"
[ -f "$proof" ] || proof="$root/scripts/proofs/$proof.proof"
proof_load "$proof" || die "$proof_error"
proof="$(cd "$(dirname "$proof")" && pwd -P)/$(basename "$proof")"
proof_name=$(basename "$proof" .proof)

resolve() {
  git -C "$root" rev-parse --verify --quiet "$1^{commit}" || die "$1 is not a commit in this repository"
}
base_sha=$(resolve "$base_ref") || exit $?
head_sha=$(resolve "$head_ref") || exit $?

mkdir -p "$out" || die "cannot create $out" 3
out=$(cd "$out" && pwd -P)
rm -rf "$out/base" "$out/head" "$out/report.json"
mkdir -p "$root/.build/SourcePackages"
work=$(mktemp -d "$root/.build/prove.XXXXXX") || die "cannot create a work folder under $root/.build" 3

expected_checks=0
for kind in "${proof_kinds[@]}"; do
  [ "$kind" != check ] || expected_checks=$((expected_checks + 1))
done

build_wrap=(${T3ISLE_PROVE_BUILD_WRAP-})
screen_wrap=(${T3ISLE_PROVE_SCREEN_WRAP-})

cleanup() {
  local side
  for side in base head; do
    [ ! -d "$work/$side" ] || git -C "$root" worktree remove --force "$work/$side" >/dev/null 2>&1
  done
  rm -rf "$work"
  git -C "$root" worktree prune
}
trap cleanup EXIT
trap 'exit 3' INT TERM

prepare() {
  local side=$1 sha=$2 tree="$work/$1"
  git -C "$root" worktree add --detach "$tree" "$sha" >&2 || die "cannot check out $sha" 3
  mkdir -p "$tree/.build"
  ln -s "$root/.build/SourcePackages" "$tree/.build/SourcePackages"
  rm -rf "$tree/scripts"
  cp -R "$root/scripts" "$tree/scripts"
}

run_side() {
  local side=$1 sha=$2 tree="$work/$1" status
  prepare "$side" "$sha"
  echo "prove: building $side ${sha:0:9}" >&2
  "${build_wrap[@]+"${build_wrap[@]}"}" "$tree/scripts/run-debug.sh" --build-only --state-dir "$work/$side-state" >&2 \
    || die "the $side build failed" 2
  "${screen_wrap[@]+"${screen_wrap[@]}"}" "$root/scripts/lib/prove-session.sh" "$side" "$tree" "$work/$side-state" "$proof" "$out/$side"
  status=$?
  case "$status" in
    0 | 1) ;;
    64) exit 3 ;;
    *) exit "$status" ;;
  esac
  recorded=$(wc -l < "$out/$side/checks.ndjson" 2>/dev/null | tr -d ' ')
  [ "${recorded:-0}" -eq "$expected_checks" ] || die "the $side session recorded ${recorded:-0} of $expected_checks checks" 3
  jq -e -s 'all(.[]; .passed)' "$out/$side/checks.ndjson" >/dev/null && return 0
  return 1
}

run_side base "$base_sha"; base_status=$?
run_side head "$head_sha"; head_status=$?

label_of() {
  local name=${1##*/}
  name=${name%.png}
  printf '%s' "${name#[0-9][0-9]-}"
}

find_shot() {
  local file
  for file in "$out/$1/captures/"[0-9][0-9]-"$2".png; do
    [ -f "$file" ] && { printf '%s' "${file#"$out/"}"; return; }
  done
}

pairs='[]'
labels=()
for file in "$out"/base/captures/*.png "$out"/head/captures/*.png; do
  [ -f "$file" ] || continue
  label=$(label_of "$file")
  case " ${labels[*]-} " in *" $label "*) continue ;; esac
  labels+=("$label")
  base_shot=$(find_shot base "$label")
  head_shot=$(find_shot head "$label")
  [ -n "$base_shot" ] && [ -n "$head_shot" ] || echo "prove: the shot $label exists on one side only" >&2
  pairs=$(jq -c --arg label "$label" --arg base "$base_shot" --arg head "$head_shot" \
    '. + [{label: $label, base: (if $base == "" then null else $base end), head: (if $head == "" then null else $head end)}]' <<< "$pairs")
done

checks_of() {
  jq -cs . "$out/$1/checks.ndjson"
}

proven=false
exit_code=1
if [ "$base_status" = 1 ] && [ "$head_status" = 0 ]; then
  proven=true
  exit_code=0
  echo "prove: proven, the base fails and the head passes" >&2
elif [ "$base_status" = 0 ]; then
  echo "prove: not proven, the base passes every check, so it does not show the bug" >&2
else
  echo "prove: not proven, the head fails a check" >&2
fi

report=$(jq -cn \
  --arg proof "$proof_name" --argjson proven "$proven" --argjson exit "$exit_code" \
  --arg baseRef "$base_ref" --arg baseSha "$base_sha" --argjson baseChecks "$(checks_of base)" \
  --arg headRef "$head_ref" --arg headSha "$head_sha" --argjson headChecks "$(checks_of head)" \
  --argjson pairs "$pairs" '
  {proof: $proof, proven: $proven, exit: $exit,
   base: {ref: $baseRef, sha: $baseSha, passed: all($baseChecks[]; .passed), checks: $baseChecks},
   head: {ref: $headRef, sha: $headSha, passed: all($headChecks[]; .passed), checks: $headChecks},
   pairs: $pairs}')
printf '%s\n' "$report" > "$out/report.json"
printf '%s\n' "$report"
exit "$exit_code"
