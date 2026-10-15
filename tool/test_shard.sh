#!/usr/bin/env bash
# One shard of every package's tests, as CI's jobs and the gate run them:
# the shard's test files (tool/shard.dart) in about PROGRAMS programs, a
# program loading once for all its files, the packages side by side, each
# package's run into OUT/<package>.json (its JSON report) and
# OUT/<package>.log (its failures); ptome's corpus held to its red list
# (tool/corpus_red.dart), and with --budget every package's run to the
# tests' time budget (tool/test_budget.dart).
#
#   tool/test_shard.sh [--budget] SHARDS INDEX PROGRAMS OUT
#
# Prints each package's verdict, and the failures of any that failed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

budget=false
if [ "${1:-}" = --budget ]; then
  budget=true
  shift
fi
if [ $# -ne 4 ]; then
  echo "usage: tool/test_shard.sh [--budget] SHARDS INDEX PROGRAMS OUT" >&2
  exit 64
fi
shards="$1" index="$2" programs="$3" out="$4"
mkdir -p "$out"

packages=()
for dir in packages/*/; do
  if [ -d "$dir/test" ]; then packages+=("$(basename "$dir")"); fi
done
dart run tool/shard.dart --programs "$programs" "$shards" "$index" \
  "${packages[@]}" > "$out/shard.txt" || exit 1

pids=()
while read -r package dir count; do
  (cd "packages/$package" &&
    dart test -j "$count" -r failures-only \
      --file-reporter "json:$out/$package.json" "$dir") \
    > "$out/$package.log" 2>&1 &
  pids+=($!)
done < "$out/shard.txt"

status=0
reports=()
i=0
while read -r package _ _; do
  wait "${pids[$i]}"
  tests=$?
  i=$((i + 1))
  reports+=("$package=$out/$package.json")
  if [ "$package" = ptome ]; then
    # (The corpus's red cases fail the run but not the shard: the red
    # list says which may.)
    verdict="$(cd packages/ptome && dart run tool/corpus_red.dart "$out/ptome.json")"
    tests=$?
  else
    verdict="$(tail -1 "$out/$package.log")"
  fi
  echo "$package: $verdict"
  if [ "$tests" -ne 0 ]; then
    status=1
    sed 's/^/  /' "$out/$package.log"
  fi
done < "$out/shard.txt"

if $budget; then
  dart run tool/test_budget.dart "${reports[@]}" || status=1
fi
exit $status
