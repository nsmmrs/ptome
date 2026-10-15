# The gate, and committing and pushing through it: run these rather than
# gate pipelines by hand. Every recipe stops at the first failure; a gate
# that isn't green stops the commit or the push.
#
#   just gate                the gate (tool/gate.sh): every check, every test
#   just commit MESSAGE_FILE the gate, then a commit of every change
#   just amend               the gate, then the changes into the last commit
#   just push                a push to master (the gate again only if the
#                            commit isn't what the gate last passed), then
#                            CI's run watched to its end
#
# The gate runs in a capped user scope (12 GB, no swap: heavy suites once
# took the terminal down), with scratch files under the work folder (/tmp
# is small), each run's output kept in its log. A green gate records the
# tree it passed (gate/green-tree), so pushing what was committed through
# it doesn't run it again.

set shell := ["bash", "-euo", "pipefail", "-c"]

work := env_var("HOME") / ".cache/asciidart-work"
logs := work / "gate"

# The recipes.
default:
    @just --list

# The gate: formatting, analysis, every package's tests, the APIs.
gate:
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p "{{work}}/tmp" "{{logs}}"
    log="{{logs}}/gate.log"
    export TMPDIR="{{work}}/tmp"
    systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 \
      bash tool/gate.sh > "$log" 2>&1
    status=$?
    # (What failed, and the verdict; the whole run is in the log.)
    grep -E 'NEW FAILURE|OVER BUDGET|^tests:|^budget:|Some tests failed|differs|== done' "$log" | head -40 || true
    tail -1 "$log"
    if [ "$status" -ne 0 ] || ! tail -1 "$log" | grep -q "gate: green"; then
      # (The gate says only that formatting or analysis failed: which files.)
      if tail -1 "$log" | grep -q 'format and analysis'; then
        dart format --output=none packages 2>&1 | grep '^Changed' || true
        dart analyze packages 2>&1 | grep -E '^ *(error|warning|info) -' | head -20 || true
      fi
      echo "just: the gate is not green (log: $log)" >&2
      exit 1
    fi

# The gate, then a commit of every change (MESSAGE_FILE with its trailers).
commit message_file: _changes _on_master
    #!/usr/bin/env bash
    set -euo pipefail
    [ -s "{{message_file}}" ] || { echo "just: no message in {{message_file}}" >&2; exit 1; }
    grep -q '^Co-Authored-By: ' "{{message_file}}" \
      || { echo "just: the message has no Co-Authored-By trailer" >&2; exit 1; }
    just gate
    git add -A
    git write-tree > "{{logs}}/green-tree"
    git commit -q -F "{{message_file}}"
    git log --oneline -1

# The gate, then the changes into the last commit (not yet pushed).
amend: _changes _on_master _unpushed
    just gate
    git add -A
    git write-tree > "{{logs}}/green-tree"
    git commit -q --amend --no-edit
    git log --oneline -1

# A push to master (the gate first unless the gate passed this very tree),
# then CI's run watched.
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
    if [ "$(cat "{{logs}}/green-tree" 2>/dev/null)" != "$(git rev-parse 'HEAD^{tree}')" ]; then
      just gate
      git rev-parse 'HEAD^{tree}' > "{{logs}}/green-tree"
    else
      echo "just: the gate passed this tree"
    fi
    git push -q origin master
    git log --oneline -1
    just ci

# CI's run of HEAD, watched to its end; fails if it failed.
ci:
    #!/usr/bin/env bash
    set -euo pipefail
    sha="$(git rev-parse HEAD)"
    id=""
    for _ in $(seq 1 60); do
      # (The run appears a few seconds after the push; a failed query, the
      # network say, is tried again.)
      id="$(gh run list --commit "$sha" --workflow CI --json databaseId -q '.[0].databaseId' 2>/dev/null)" || true
      [ -n "$id" ] && break
      sleep 2
    done
    [ -n "$id" ] || { echo "just: CI's run of $sha could not be found" >&2; exit 1; }
    if ! gh run watch "$id" --exit-status --interval 5 > "{{logs}}/ci.log" 2>&1; then
      gh run view "$id" --json jobs -q '.jobs[] | select(.conclusion != "success") | "\(.conclusion)  \(.name)"' || true
      echo "just: CI is not green for $sha (gh run view $id --log-failed)" >&2
      exit 1
    fi
    gh run view "$id" --json createdAt,updatedAt -q '"success  CI in \(((.updatedAt|fromdate)-(.createdAt|fromdate)))s"'

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
