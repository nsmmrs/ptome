#!/usr/bin/env bash
# The tests run the same everywhere: none looks for a tool on the path, in
# the machine's font folders, or for a font being installed, to do one
# thing or another (or skip). What a tool answers is recorded
# (test/support/oracles.dart); the fonts are the tests' own. A line can
# say why it is none of those, `// hermetic: …` on it or the line before;
# test/frozen holds frozen copies of library code, left out.
set -euo pipefail
cd "$(dirname "$0")/.."
export pattern="runSync[(]'which'|command -v|/usr/share/fonts|/Library/Fonts|Fonts[.]installed[.]find[(]|FontFiles[.]platform"
found="$(find packages/*/test -name '*.dart' -not -path '*/frozen/*' -print0 |
  xargs -0 awk '
    FNR == 1 { before = "" }
    $0 ~ ENVIRON["pattern"] && $0 !~ /hermetic:/ && before !~ /hermetic:/ {
      print FILENAME ":" FNR ": " $0
    }
    { before = $0 }
  ')"
if [ -n "$found" ]; then
  echo "tests that depend on the machine (tool/hermetic_check.sh):"
  echo "$found"
  exit 1
fi
