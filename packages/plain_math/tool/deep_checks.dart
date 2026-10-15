/// The equivalence tests run deeper, by hand: many times the fuzzed
/// inputs the tests check (the digests not checked then). A case it finds
/// failing becomes a fixed case in the test.
///
/// ```sh
/// dart run tool/deep_checks.dart [SCALE]   # 10 by default
/// ```
library;

import '../test/equivalence_test.dart' as equivalence;

void main(List<String> args) {
  equivalence.equivalence(scale: args.isEmpty ? 10 : int.parse(args.first));
}
