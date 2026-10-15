#!/usr/bin/env bash
# The packages' copies of the shared test helpers (test/support/oracles.dart,
# the oracles' recorded answers; test/support/pdf_tools.dart, the PDF
# tools' recorded runs) are one file each: every copy must be the same as
# the first.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for helper in oracles pdf_tools; do
  copies=(packages/*/test/support/$helper.dart)
  for copy in "${copies[@]:1}"; do
    cmp -s "${copies[0]}" "$copy" || {
      echo "$copy differs from ${copies[0]}"
      status=1
    }
  done
done
exit $status
