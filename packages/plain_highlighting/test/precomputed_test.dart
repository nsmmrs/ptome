// The precomputed first characters and group counts
// (lib/src/first_chars_table.g.dart): what the grammars give today, and
// read back as they were written.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_highlighting/plain_highlighting.dart';
import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/first_chars_table.g.dart';
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/precomputed.dart';
import 'package:test/test.dart';

void main() {
  test('the table is what the grammars give', () {
    expect(
      base64Encode(buildPrecomputedTable()) == precomputedTable,
      isTrue,
      reason: 'run: dart run tool/generate_first_chars.dart',
    );
  });

  test('every entry reads back as it was written', () {
    final table = base64Decode(precomputedTable);
    var entries = 0;
    for (final (name, _, _) in allLanguages) {
      final display = Highlighting().displayName(name)!;
      final rules = precomputedRules(display);
      expect(rules, isNotNull, reason: display);
      for (final (_, at) in rules!) {
        final (first, end) = decodeFirstChars(table, at);
        final out = BytesBuilder();
        encodeFirstChars(first, out);
        expect(out.takeBytes(), Uint8List.sublistView(table, at, end));
        entries++;
      }
    }
    expect(entries, greaterThan(4000));
  });

  test('highlighting reads the table, with the same result', () {
    // (A language seen first here: its matchers built from the table.)
    final html = Highlighting()
        .highlight(
          '<div class="a">x</div><script>let a = 1;</script>',
          language: 'html',
        )
        .html;
    expect(html, contains('<span class="hljs-tag">'));
    expect(html, contains('<span class="hljs-keyword">let</span>'));
  });
}
