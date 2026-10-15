// The flow layout against what plain_typesetting made of the same
// random documents (test/fixtures/flow_digests.txt): its caches and
// shortcuts may not change a page, a coordinate or an anchor, in a first
// layout or in one done again by the same FlowLayout. Every third seed;
// tool/deep_checks.dart lays out every one.
import 'dart:io';

import 'package:test/test.dart';

import 'support/random_flow.dart';

void main() => flowEquivalence();

/// The flow tests over every [every]th seed of the digests.
void flowEquivalence({int every = 3}) {
  final expected = <int, String>{
    for (final line in File('test/fixtures/flow_digests.txt').readAsLinesSync())
      if (!line.startsWith('#') && !line.endsWith(' skip'))
        int.parse(line.split(' ')[0]): line.split(' ').skip(1).join(' '),
  };

  test('random documents laid out as before, bit for bit', () {
    for (final (i, MapEntry(key: seed, value: digested))
        in expected.entries.indexed) {
      if (i % every != 0) continue;
      final (content, layout) = RandomFlow(seed).build();
      final first = renderExactly(layout, content);
      expect(
        '${digest(first)} ${first.length}',
        digested,
        reason: 'seed $seed',
      );
      // Again, with what the layout kept from the first time.
      final again = renderExactly(layout, content);
      expect(again, first, reason: 'seed $seed laid out again');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
