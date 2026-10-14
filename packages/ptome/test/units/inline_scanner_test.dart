// The units inline scanner's markers, found by trying the marker pattern
// only at the first `@` of each run, are the ones the pattern's
// allMatches finds over the whole line (the regex kept here as the
// oracle), on random lines of markers, labels, brackets, letters of
// several scripts, digits and spaces.
import 'dart:math';

import 'package:ptome/src/units/document.dart';
import 'package:test/test.dart';

/// The marker pattern as the scanner held it before it searched for `@`.
final RegExp _oracle = RegExp(
  r'(?<![\p{L}\p{N}_@\\])(@+)(\^\S*|[^\s\[\]@]*)(\[[^\]\n]*\])?(?=\s|$)',
  unicode: true,
);

void main() {
  test('markers as the whole-line pattern finds them', () {
    const pieces = [
      '@', '@', '@@', '@^', '^', '[', ']', '[n=1]', 'a', 'Z', '1', '_', //
      r'\', ' ', ' ', '\t', '\n', 'λ', 'Ω', 'א', '٣', '日', '-', '.', 'x@',
      '😀',
    ];
    final random = Random(14);
    for (var n = 0; n < 50000; n++) {
      final text = [
        for (var i = random.nextInt(12); i >= 0; i--)
          pieces[random.nextInt(pieces.length)],
      ].join();
      String show(Iterable<Match> ms) =>
          [for (final m in ms) '${m.start}-${m.end}:${m[1]}|${m[2]}|${m[3]}']
              .join(' ');
      expect(
        show(InlineScanner.markers(text)),
        show(_oracle.allMatches(text)),
        reason: text,
      );
    }
  });
}
