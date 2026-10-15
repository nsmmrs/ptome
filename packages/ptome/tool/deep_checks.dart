/// The tests' property checks run deeper, by hand: each over many times
/// the random cases the tests run (the same seeds, then on). A case it
/// finds failing becomes a fixed case in the test.
///
/// ```sh
/// dart run tool/deep_checks.dart [SCALE]   # 100 by default
/// ```
library;

import '../test/scan_guards_test.dart' as scan_guards;

void main(List<String> args) {
  final scale = args.isEmpty ? 100 : int.parse(args.first);
  scan_guards.properties(scale: scale);
}
