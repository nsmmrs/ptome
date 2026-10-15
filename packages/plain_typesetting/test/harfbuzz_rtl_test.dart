// Right-to-left text (Arabic with its vowels, joining forms and lam-alef
// ligatures; Hebrew with its points) shaped by the OpenType layout tables
// in full, against HarfBuzz (harfbuzzjs, in tool/oracles/harfbuzz,
// installed by tool/oracles/setup.sh): the same glyphs in the same visual
// order, the same advances and the same mark offsets, for each line of
// test/fixtures/shaping-rtl.txt in the subset Noto fonts of test/fonts.
// HarfBuzz's answers are recorded in test/oracles/harfbuzz_rtl.json
// (test/support/oracles.dart; ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

const String _shape = 'tool/oracles/harfbuzz/shape.mjs';

/// The oracle's version, which its answers depend on.
const String _harfbuzzjs = 'harfbuzzjs 1.6.3';

void main() {
  final recorded = Oracle('harfbuzz_rtl');
  final lines = File('test/fixtures/shaping-rtl.txt')
      .readAsLinesSync()
      .where((l) => l.isNotEmpty)
      .toList();
  for (final (name, script) in [
    ('notonaskharabic-subset.ttf', RegExp('[؀-ۿ]')),
    ('notoserifhebrew-subset.ttf', RegExp('[֐-׿]')),
  ]) {
    test('$name shapes right-to-left text as HarfBuzz does', () {
      final path = 'test/fonts/$name';
      final bytes = File(path).readAsBytesSync();
      final font = OpenTypeShaper(OpenTypeFont.parse(bytes));
      final upem = font.font.unitsPerEm;
      final mine = [
        for (final line in lines)
          if (script.hasMatch(line)) line,
      ];
      final theirs = recorded
          .json<List<Object?>>(
            name,
            inputs: [_harfbuzzjs, bytes, ...mine],
            oracle: () => _harfbuzz(path, mine),
          )
          .cast<List<Object?>>();
      final differ = <String>[];
      for (final (i, line) in mine.indexed) {
        int units(double v) => (v * upem / 1000).round();
        final ours = [
          for (final g in font.shape(line, rightToLeft: true))
            [g.id, units(g.advance), units(g.xOffset), units(g.yOffset)],
        ];
        final expected = [
          for (final g in theirs[i].cast<List<Object?>>())
            [g[0], g[2], g[3], g[4]],
        ];
        if (jsonEncode(ours) != jsonEncode(expected)) {
          differ.add('$line\n    ours:     $ours\n    HarfBuzz: $expected');
        }
      }
      expect(differ, isEmpty, reason: differ.take(3).join('\n'));
    });
  }
}

/// HarfBuzz's [glyph, cluster, advance, x offset, y offset] glyphs of each
/// of [lines] in [font], in visual order.
List<List<Object?>> _harfbuzz(String font, List<String> lines) {
  final dir = Directory.systemTemp.createTempSync('harfbuzz_oracle.');
  try {
    final file = File('${dir.path}/input')
      ..writeAsStringSync(
        jsonEncode({
          'font': font,
          'detail': true,
          'runs': [
            for (final line in lines) {'text': line, 'features': <String>[]},
          ],
        }),
      );
    final r = Process.runSync('sh', [
      '-c',
      'node "\$0" < "${file.path}"',
      _shape,
    ]);
    if (r.exitCode != 0) throw StateError('HarfBuzz: ${r.stderr}');
    return (jsonDecode(r.stdout as String) as List).cast<List<Object?>>();
  } finally {
    dir.deleteSync(recursive: true);
  }
}
