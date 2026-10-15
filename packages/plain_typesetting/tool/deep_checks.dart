/// The tests' random checks run deeper, by hand: every seed of the flow
/// digests, and many times the optimality tests' random paragraphs. A
/// case it finds failing becomes a fixed case in the test.
///
/// ```sh
/// dart run tool/deep_checks.dart [SCALE]   # 10 by default
/// ```
library;

import '../test/flow_equivalence_test.dart' as flow;
import '../test/knuth_plass_optimal_test.dart' as optimal;
import '../test/lined_content_test.dart' as lined;

void main(List<String> args) {
  flow.flowEquivalence(every: 1);
  lined.linedContent(every: 1);
  optimal.optimal(scale: args.isEmpty ? 10 : int.parse(args.first));
}
