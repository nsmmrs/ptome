#!/usr/bin/env bash
# Every package's tests RUNS times over, as the gate runs them (a program
# a core, tool/shard.dart --programs), each run's tests in an order of
# its own (a random seed, printed): a test that fails in one run and not
# another is a flake, to be fixed at its cause. By hand, not a gate.
#
#   tool/flake_hunt.sh [RUNS]     # 20 by default
#
# Prints each run's seed and verdict, and the failures of a run that
# failed, its reports kept in $TMPDIR/ptome-flake-hunt/<run>.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
export PTOME_SYSTEM_FONTS=off SOURCE_DATE_EPOCH=1767225600 TZ=UTC
unset PTOME_FONT_PATH

runs="${1:-20}"
work="${TMPDIR:-/tmp}/ptome-flake-hunt"
cores="$(nproc 2> /dev/null || sysctl -n hw.ncpu)"
rm -rf "$work" && mkdir -p "$work"

packages=()
for dir in packages/*/; do
  if [ -d "$dir/test" ]; then packages+=("$(basename "$dir")"); fi
done
dart run tool/shard.dart --programs "$cores" 1 0 "${packages[@]}" \
  > "$work/shard.txt" || exit 1

failed=0
for run in $(seq "$runs"); do
  out="$work/$run"
  mkdir -p "$out"
  seed=$RANDOM$RANDOM
  pids=()
  while read -r package dir count; do
    (cd "packages/$package" &&
      dart test -j "$count" -r failures-only \
        --test-randomize-ordering-seed="$seed" \
        --file-reporter "json:$out/$package.json" "$dir") \
      > "$out/$package.log" 2>&1 &
    pids+=($!)
  done < "$work/shard.txt"
  bad=()
  i=0
  while read -r package _ _; do
    wait "${pids[$i]}" || bad+=("$package")
    i=$((i + 1))
  done < "$work/shard.txt"
  if [ ${#bad[@]} -eq 0 ]; then
    echo "run $run (seed $seed): green"
  else
    failed=$((failed + 1))
    echo "run $run (seed $seed): FAILED in ${bad[*]}"
    for package in "${bad[@]}"; do sed 's/^/  /' "$out/$package.log"; done
  fi
done
echo "flake hunt: $((runs - failed)) of $runs runs green"
[ "$failed" -eq 0 ]
