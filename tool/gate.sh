#!/usr/bin/env bash
# The quality gate, in two tiers (ADR-0022):
#
#   tool/gate.sh [fast]   every commit, about half a minute: formatting,
#                         analysis, and ptome's tests but the slow ones (the
#                         corpus included, held to test/corpus/red.txt)
#   tool/gate.sh full     before a push: the same over every test, the API
#                         and JavaScript projection checks, the CLI
#                         on a built executable (bats), and the plain_*
#                         packages' tests (but the nightly ones) and APIs
#   tool/gate.sh ptome    the full tier's ptome part alone (CI's gate job;
#                         its workspace job runs the packages)
#
# The parts that don't depend on each other run at the same time, each
# into a log printed when all are done, with the time it took. Node.js and
# the npm package run in CI's npm job, the live oracles (the gem,
# asciidoctor-epub3, EPUBCheck) and the tests tagged nightly in the
# nightly workflow. Tools a step needs and the machine lacks (pdftoppm,
# unzip, bats) skip that step with a note; CI has them. Scratch files go
# to $TMPDIR (default /tmp).
set -uo pipefail
# The tests' world, the same on every machine (CI's workflow sets it too):
# no font installed on the machine, only the ones they name; one date and
# time zone, so the files they write are the same bytes every run (the
# tools' answers are recorded for those bytes).
export PTOME_SYSTEM_FONTS=off SOURCE_DATE_EPOCH=1767225600 TZ=UTC
unset PTOME_FONT_PATH
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
have() { command -v "$1" >/dev/null 2>&1; }

# (Internal: one plain_* package's tests and API, for the parallel run.)
if [ "${1:-}" = _package ]; then
  cd "$root/$2" || exit 1
  status=0
  dart test -r failures-only | tail -1 || status=1
  if [ -f tool/api_check.dart ]; then
    dart run tool/api_check.dart | tail -1 || status=1
  fi
  exit $status
fi

tier="${1:-fast}"
case "$tier" in fast|full|ptome) ;; *) echo "usage: tool/gate.sh [fast|full|ptome]" >&2; exit 64 ;; esac
work="${TMPDIR:-/tmp}/ptome-gate"
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
  cd "$root" || return 1
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

# ptome's tests (the fast tier's: but the slow ones), held to the corpus's
# red list; the full tier's over every test, then the CLI on the built
# executable.
ptome_tests() {
  cd "$root/packages/ptome" || return 1
  have pdftoppm || echo "(no pdftoppm: PDF pages are compared by hash only)"
  local status=0 t=$SECONDS
  if [ "$tier" = fast ]; then
    dart test -x slow --file-reporter "json:$work/tests.json" \
      -r failures-only > "$work/tests.log" 2>&1
  else
    dart compile exe -o "$work/ptome" bin/ptome.dart >/dev/null || {
      echo "the executable didn't build"
      return 1
    }
    echo "built the executable ($((SECONDS - t))s)"
    t=$SECONDS
    dart test --file-reporter "json:$work/tests.json" -r failures-only \
      > "$work/tests.log" 2>&1
  fi
  dart run tool/corpus_red.dart "$work/tests.json" || {
    echo "(the run's output: $work/tests.log)"
    status=1
  }
  echo "(tests: $((SECONDS - t))s)"
  [ "$tier" = fast ] && return $status
  if have bats; then
    t=$SECONDS
    ASCIIDOCTOR_EXE="$work/ptome" bats test/e2e/ > "$work/bats.log" 2>&1 || {
      grep '^not ok' "$work/bats.log"
      status=1
    }
    echo "bats: $(tail -1 "$work/bats.log") ($((SECONDS - t))s)"
  else
    echo "(no bats: the CLI tests skipped)"
  fi
  return $status
}

api_and_js() {
  cd "$root/packages/ptome" || return 1
  local status=0
  dart run tool/api_check.dart | tail -1 || status=1
  dart run tool/generate_js.dart --check || status=1
  return $status
}

# The plain_* packages, three at a time (each `dart test` runs its own
# files in parallel too).
packages() {
  cd "$root" || return 1
  local status=0 pkg name
  for pkg in packages/plain_*/; do echo "${pkg%/}"; done |
    xargs -P 3 -I{} bash -c \
      '"$0" _package "$1" > "$2/$(basename "$1").log" 2>&1 || touch "$2/$(basename "$1").failed"' \
      "$root/tool/gate.sh" {} "$work"
  for pkg in packages/plain_*/; do
    name="$(basename "$pkg")"
    echo "$name: $(tr '\n' ' ' < "$work/$name.log")"
    [ -e "$work/$name.failed" ] && status=1
  done
  return $status
}

spawn "format and analysis" format_and_analyze
spawn "ptome tests" ptome_tests
if [ "$tier" != fast ]; then
  spawn "public API and JavaScript projection" api_and_js
fi
if [ "$tier" = full ]; then
  spawn "plain_* packages" packages
fi
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
  echo "gate ($tier): green"
else
  echo "gate ($tier): FAILED: ${failed[*]}"
  exit 1
fi
