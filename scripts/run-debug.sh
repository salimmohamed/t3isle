#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
app="$root/.build/DerivedData/Build/Products/Debug/T3 Isle.app"
executable="$app/Contents/MacOS/T3 Isle"
build_log="$root/.build/run-debug-build.log"
state="$root/.build/debug-state"
build=1
app_arguments=()

json_string() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

finish() {
  local pid=$1 error=${2:-}
  local line
  line="{\"app\":$(json_string "$app"),\"pid\":$pid,\"log\":$(json_string "$state/logs/events.ndjson")"
  line+=",\"state\":$(json_string "$state/logs/state.json"),\"stateDir\":$(json_string "$state")"
  if [ -n "$error" ]; then
    line+=",\"error\":$(json_string "$error")}"
  else
    line+="}"
    printf '%s\n' "$line" > "$state/run.json"
  fi
  printf '%s\n' "$line"
}

fail() {
  echo "run-debug: $2" >&2
  finish "${3:-null}" "$2"
  exit "$1"
}

pids_using_state() {
  ps -axww -o pid=,args= | awk -v exe="$executable " -v flag=" --state-dir $state" '
    {
      pid = $1
      sub(/^ *[0-9]+ /, "")
      if (index($0, exe) == 1 && (index($0, flag " ") || substr($0, length($0) - length(flag) + 1) == flag)) print pid
    }'
}

has_window() {
  [ -n "$(osascript -l JavaScript "$root/scripts/lib/windows.js" "$1" 2>/dev/null)" ]
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) build=0 ;;
    --state-dir)
      [ $# -ge 2 ] || fail 3 "--state-dir needs a path"
      state=$2
      shift
      ;;
    *) app_arguments+=("$1") ;;
  esac
  shift
done

mkdir -p -m 700 "$state" || fail 3 "cannot create state dir $state"
state=$(cd "$state" && pwd -P)

running=$(pids_using_state | head -n 1)
[ -z "$running" ] || fail 3 "a copy already runs with this state dir, stop it with scripts/stop-debug.sh $running" "$running"

if [ "$build" = 1 ]; then
  mkdir -p "$root/.build"
  echo "run-debug: building the Debug app, log in $build_log" >&2
  if ! (cd "$root" && xcodebuild build -scheme boringNotch \
    -project boringNotch.xcodeproj \
    -configuration Debug \
    -destination platform=macOS,arch=arm64 \
    -derivedDataPath "$root/.build/DerivedData" \
    -clonedSourcePackagesDirPath "$root/.build/SourcePackages" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO) > "$build_log" 2>&1; then
    fail 2 "build failed, see $build_log"
  fi
fi
[ -x "$executable" ] || fail 2 "no Debug build at $app, run without --no-build"

if [ -n "${T3ISLE_SIGN_IDENTITY:-}" ]; then
  sign=(codesign --force --deep --preserve-metadata=entitlements,flags,runtime -s "$T3ISLE_SIGN_IDENTITY")
  [ -n "${T3ISLE_SIGN_KEYCHAIN:-}" ] && sign+=(--keychain "$T3ISLE_SIGN_KEYCHAIN")
  if [[ "$T3ISLE_SIGN_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    signer="certificate leaf = H\"$T3ISLE_SIGN_IDENTITY\""
    sign+=("-r=designated => $signer")
  else
    signer="certificate leaf[subject.CN] = \"$T3ISLE_SIGN_IDENTITY\""
  fi
  if codesign --verify --deep --strict -R="$signer" "$app" 2>/dev/null; then
    echo "run-debug: the app is already signed by T3ISLE_SIGN_IDENTITY, keeping its signature" >&2
  else
    "${sign[@]}" "$app" >&2 || fail 2 "codesign failed for $app"
  fi
else
  echo "run-debug: T3ISLE_SIGN_IDENTITY is not set, so the app keeps its build signature and macOS may ask for permissions again" >&2
fi

rm -f "$state/run.json"

defaults read "$state/defaults" firstLaunch >/dev/null 2>&1 || defaults write "$state/defaults" firstLaunch -bool false

open -n -g -a "$app" --args --state-dir "$state" ${app_arguments[@]+"${app_arguments[@]}"} >&2 \
  || fail 3 "open could not launch $app"

pid=""
for _ in $(seq 1 120); do
  pid=$(pids_using_state | head -n 1)
  [ -n "$pid" ] && break
  sleep 0.25
done
[ -n "$pid" ] || fail 3 "the app did not start within 30 seconds"

for _ in $(seq 1 120); do
  kill -0 "$pid" 2>/dev/null || fail 3 "the app (pid $pid) exited during launch"
  has_window "$pid" && break
  sleep 0.25
done
has_window "$pid" || fail 3 "the app (pid $pid) showed no window within 30 seconds" "$pid"

for _ in $(seq 1 120); do
  [ -f "$state/logs/events.ndjson" ] && break
  sleep 0.25
done
[ -f "$state/logs/events.ndjson" ] || fail 3 "the app (pid $pid) started no event log within 30 seconds" "$pid"

finish "$pid"
