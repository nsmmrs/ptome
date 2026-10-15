#!/usr/bin/env bash
# The packages' copies of test/support/oracles.dart (the oracles'
# recorded answers) are one file: each must be the same as the first.
set -euo pipefail
cd "$(dirname "$0")/.."
copies=(packages/*/test/support/oracles.dart)
status=0
for copy in "${copies[@]:1}"; do
  cmp -s "${copies[0]}" "$copy" || {
    echo "$copy differs from ${copies[0]}"
    status=1
  }
done
exit $status
