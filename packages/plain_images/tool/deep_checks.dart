/// The tests' random checks run deeper, by hand: many times the cases the
/// tests check (the same seeds, then on). A case it finds failing becomes
/// a fixed case in the test.
///
/// ```sh
/// dart run tool/deep_checks.dart [SCALE]   # 10 by default
/// ```
library;

import '../test/fuzz_test.dart' as fuzz;

void main(List<String> args) {
  fuzz.fuzz(scale: args.isEmpty ? 10 : int.parse(args.first));
}
