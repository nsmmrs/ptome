#!/usr/bin/env bash
# The gate, one for every commit and every push (`just commit`, `just push`;
# CI runs the same checks, spread over its jobs):
#
#   - the workspace formatted and analyzed, the packages' shared test
#     helpers alike (tool/oracles_check.sh), no test depending on the
#     machine (tool/hermetic_check.sh);
#   - every package's whole suite, in the tests' world (below), ptome's
#     corpus held to test/corpus/red.txt;
#   - the public APIs against their snapshots, ptome's JavaScript
#     projection against its generator.
#
# The tests' time budget (tool/test_budget.dart) is CI's: its runners'
# times, a job each, where this machine's depend on what else it runs.
#
#   tool/gate.sh
#
# The parts run side by side, each into a log printed when all are done,
# with the time it took. Scratch files go to $TMPDIR (default /tmp).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

# The tests' world, the same on every machine (CI's workflow sets it too):
# no font installed on the machine, only the ones they name; one date and
# time zone, so the files they write are the same bytes every run (the
# tools' answers are recorded for those bytes).
export PTOME_SYSTEM_FONTS=off SOURCE_DATE_EPOCH=1767225600 TZ=UTC
unset PTOME_FONT_PATH

work="${TMPDIR:-/tmp}/ptome-gate"
cores="$(nproc 2>/dev/null || echo 4)"

rm -rf "$work" && mkdir -p "$work"

# The jobs started, as `name|log`; each writes `<status> <seconds>` beside
# its log when it ends.
jobs_started=()
spawn() {
  local name="$1"
  shift
  local log="$work/job-${#jobs_started[@]}.log"
  jobs_started+=("$name|$log")
  (
    start=$SECONDS
    "$@" > "$log" 2>&1
    echo "$? $((SECONDS - start))" > "$log.status"
  ) &
}

format_and_analyze() {
  local status=0
  dart format --output=none --set-exit-if-changed packages >/dev/null || {
    echo "formatting differs (dart format packages)"
    status=1
  }
  dart analyze --fatal-infos . | tail -1 || status=1
  tool/oracles_check.sh || status=1
  tool/hermetic_check.sh || status=1
  return $status
}

# Every package's suite, as one of CI's shards runs its part
# (tool/test_shard.sh): the packages side by side, in a program a core.
suites() {
  tool/test_shard.sh 1 0 "$cores" "$work/tests"
}

apis_and_js() {
  local status=0
  (cd packages/ptome && dart run tool/generate_js.dart --check) &
  local js=$!
  dart run tool/api_check.dart > "$work/api.log" 2>&1 || status=1
  # (What differs, or one line saying all match.)
  grep -v 'public API matches' "$work/api.log" ||
    echo "every public API matches its snapshot"
  wait "$js" || status=1
  return $status
}

spawn "format and analysis" format_and_analyze
spawn "the suites" suites
spawn "public APIs and JavaScript projection" apis_and_js
wait

failed=()
for entry in "${jobs_started[@]}"; do
  name="${entry%%|*}"
  log="${entry#*|}"
  read -r status seconds < "$log.status"
  printf '== %s (%ss)\n' "$name" "$seconds"
  cat "$log"
  [ "$status" = 0 ] || failed+=("$name")
done
echo "== done in ${SECONDS}s"
if [ ${#failed[@]} -eq 0 ]; then
  echo "gate: green"
else
  echo "gate: FAILED: ${failed[*]}"
  exit 1
fi
