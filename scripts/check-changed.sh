#!/bin/bash
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root" || exit 2
tests_dir=T3IsleCore/Tests/T3IsleCoreTests
ref=${1:-origin/main}

base=$(git merge-base HEAD "$ref" 2>/dev/null) \
  || { echo "check-changed: no merge base with $ref. Run git fetch or pass a ref." >&2; exit 2; }
changed=$({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
summary=()
failed=0
full_suite=0
classes=""
unmapped=()

run_step() {
  local name=$1 started=$SECONDS log="$work/step.log"
  shift
  echo "check-changed: $name" >&2
  if "$@" > "$log" 2>&1; then
    summary+=("  pass  $name  $((SECONDS - started))s")
  else
    cat "$log" >&2
    summary+=("  FAIL  $name  $((SECONDS - started))s")
    failed=1
  fi
}

lint() {
  command -v swiftlint >/dev/null 2>&1 || { echo "SwiftLint is missing. Install it with: brew install swiftlint"; return 1; }
  local snapshot="$work/lint" file
  mkdir -p "$snapshot"
  cp .swiftlint.yml "$snapshot/"
  for file in "${swift_files[@]}"; do
    mkdir -p "$snapshot/$(dirname "$file")"
    cp "$file" "$snapshot/$file"
  done
  .githooks/lint-swift "$snapshot"
}

test_classes_in() {
  sed -nE 's/.*class ([A-Za-z0-9_]+)[[:space:]]*:[[:space:]]*XCTestCase.*/\1/p' "$1"
}

add_test_file() {
  local found
  found=$(test_classes_in "$1")
  if [ -z "$found" ]; then
    full_suite=1
  else
    classes+="$found"$'\n'
  fi
}

swift_files=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    *.swift) [ -f "$file" ] && swift_files+=("$file") ;;
  esac
  case "$file" in
    T3IsleCore/Package.swift|T3IsleCore/Package.resolved) full_suite=1 ;;
    "$tests_dir"/Fixtures/*)
      stem=$(basename "$file")
      users=$(grep -lF "${stem%.*}" "$tests_dir"/*.swift)
      if [ -n "$users" ]; then
        for user in $users; do add_test_file "$user"; done
      else
        unmapped+=("$file")
      fi
      ;;
    "$tests_dir"/*.swift) [ -f "$file" ] && add_test_file "$file" ;;
    T3IsleCore/Sources/*.swift)
      [ -f "$file" ] || continue
      owner=$(grep -lE "class $(basename "$file" .swift)Tests[[:space:]]*:[[:space:]]*XCTestCase" "$tests_dir"/*.swift | head -n 1)
      if [ -n "$owner" ]; then
        add_test_file "$owner"
      else
        unmapped+=("$file")
      fi
      ;;
  esac
done <<< "$changed"

if [ ${#swift_files[@]} -gt 0 ]; then
  run_step "lint, ${#swift_files[@]} Swift files" lint
else
  summary+=("  skip  lint: no Swift files changed")
fi

classes=$(printf '%s' "$classes" | sort -u | paste -sd '|' -)
if [ "$full_suite" = 1 ]; then
  run_step "T3IsleCore tests, full suite" swift test --package-path T3IsleCore
elif [ -n "$classes" ]; then
  run_step "T3IsleCore tests: ${classes//|/, }" \
    swift test --package-path T3IsleCore --filter "T3IsleCoreTests\\.($classes)/"
else
  summary+=("  skip  T3IsleCore tests: no changed file maps to a test class")
fi

ci_also="the Xcode build and scheme tests, the release script tests"
[ "$full_suite" = 1 ] || ci_also="the full T3IsleCore suite, $ci_also"

echo
echo "check-changed summary (base ${base:0:7} from $ref, $(printf '%s\n' "$changed" | grep -c .) changed files)"
printf '%s\n' "${summary[@]}"
[ ${#unmapped[@]} -eq 0 ] || echo "  no test file for: ${unmapped[*]}"
echo "  CI also runs: $ci_also"
exit "$failed"
