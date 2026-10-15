# The gates, and committing and pushing through them (ADR-0022): run these
# rather than gate pipelines by hand. Every recipe stops at the first
# failure; a gate that isn't green stops the commit or the push.
#
#   just fast                the fast gate (about half a minute)
#   just full                the full gate (a few minutes)
#   just commit MESSAGE_FILE the fast gate, then a commit of every change
#   just amend               the fast gate, then the changes into the last commit
#   just push                the full gate, then a push to master, then CI
#
# The gates run in a capped user scope (12 GB, no swap: the heavy suites
# once took the terminal down), with scratch files under the work folder
# (/tmp is small), each run's output kept in its log.

set shell := ["bash", "-euo", "pipefail", "-c"]

work := env_var("HOME") / ".cache/asciidart-work"
logs := work / "gate"

# The recipes.
default:
    @just --list

# The fast gate: formatting, analysis, ptome's tests but the slow ones.
fast: (_gate "fast")

# The full gate: every test, APIs, the CLI, the plain_* packages.
full: (_gate "full")

_gate tier:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p "{{work}}/tmp" "{{logs}}"
    log="{{logs}}/{{tier}}.log"
    export TMPDIR="{{work}}/tmp"
    export CHROMIUM_PATH="${CHROMIUM_PATH:-/usr/bin/chromium}"
    systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 \
      bash tool/gate.sh {{tier}} > "$log" 2>&1
    status=$?
    # (What failed, and the verdict; the whole run is in the log.)
    grep -E 'NEW FAILURE|^tests:|Some tests failed' "$log" | head -40 || true
    tail -1 "$log"
    if [ "$status" -ne 0 ] || ! tail -1 "$log" | grep -q "gate ({{tier}}): green"; then
      # (The gate says only that formatting or analysis failed: which files.)
      if tail -1 "$log" | grep -q 'format and analysis'; then
        dart format --output=none packages 2>&1 | grep '^Changed' || true
        dart analyze packages 2>&1 | grep -E '^ *(error|warning|info) -' | head -20 || true
      fi
      echo "just: the {{tier}} gate is not green (log: $log)" >&2
      exit 1
    fi

# The fast gate, then a commit of every change (MESSAGE_FILE with its trailers).
commit message_file: _changes _on_master
    #!/usr/bin/env bash
    set -euo pipefail
    [ -s "{{message_file}}" ] || { echo "just: no message in {{message_file}}" >&2; exit 1; }
    grep -q '^Co-Authored-By: ' "{{message_file}}" \
      || { echo "just: the message has no Co-Authored-By trailer" >&2; exit 1; }
    just fast
    git add -A
    git commit -q -F "{{message_file}}"
    git log --oneline -1

# The fast gate, then the changes into the last commit (not yet pushed).
amend: _changes _on_master _unpushed
    just fast
    git add -A
    git commit -q --amend --no-edit
    git log --oneline -1

# The full gate on what is committed, then a push to master, then CI watched.
push: _clean _on_master
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch -q origin master
    if ! git merge-base --is-ancestor origin/master HEAD; then
      echo "just: origin/master has commits this branch lacks" >&2
      exit 1
    fi
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ]; then
      echo "just: nothing to push"
      exit 0
    fi
    just full
    git push -q origin master
    git log --oneline -1
    just ci

# CI's runs of HEAD, waited for (up to 40 minutes); fails if one failed.
ci:
    #!/usr/bin/env bash
    set -euo pipefail
    sha="$(git rev-parse HEAD)"
    runs=""
    for _ in $(seq 1 80); do
      sleep 30
      # (A failed query, the network say, is tried again.)
      runs="$(gh run list --commit "$sha" --json name,status,conclusion 2>/dev/null)" || continue
      [ "$(jq length <<< "$runs")" -gt 0 ] || continue
      [ "$(jq '[.[] | select(.status != "completed")] | length' <<< "$runs")" -eq 0 ] && break
    done
    [ -n "${runs:-}" ] || { echo "just: CI's runs could not be read" >&2; exit 1; }
    jq -r '.[] | "\(.conclusion // .status)  \(.name)"' <<< "$runs"
    if jq -e '[.[] | select(.status != "completed" or (.conclusion != "success" and .conclusion != "skipped"))] | length > 0' <<< "$runs" > /dev/null; then
      echo "just: CI is not green for $sha" >&2
      exit 1
    fi

_changes:
    @[ -n "$(git status --porcelain)" ] || { echo "just: nothing to commit" >&2; exit 1; }

_clean:
    @[ -z "$(git status --porcelain)" ] || { echo "just: uncommitted changes; commit them first" >&2; git status --short >&2; exit 1; }

_on_master:
    @[ "$(git branch --show-current)" = master ] || { echo "just: not on master" >&2; exit 1; }

_unpushed:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch -q origin master
    if git merge-base --is-ancestor HEAD origin/master; then
      echo "just: the last commit is pushed; make a new one" >&2
      exit 1
    fi
