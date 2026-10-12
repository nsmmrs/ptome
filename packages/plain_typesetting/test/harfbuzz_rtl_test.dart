// Right-to-left text (Arabic with its vowels, joining forms and lam-alef
// ligatures; Hebrew with its points) shaped by the OpenType layout tables
// in full, against HarfBuzz (harfbuzzjs, in tool/oracles/harfbuzz,
// installed by tool/oracles/setup.sh; skipped where it isn't): the same
// glyphs in the same visual order, the same advances and the same mark
// offsets, for each line of test/fixtures/shaping-rtl.txt in the subset
// Noto fonts of test/fonts.
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

const String _shape = 'tool/oracles/harfbuzz/shape.mjs';

void main() {
  final ready = Directory('tool/oracles/harfbuzz/node_modules').existsSync();
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
      final font = OpenTypeShaper(
        OpenTypeFont.parse(File(path).readAsBytesSync()),
      );
      final upem = font.font.unitsPerEm;
      final mine = [
        for (final line in lines)
          if (script.hasMatch(line)) line,
      ];
      final theirs = _harfbuzz(path, mine);
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
    }, skip: ready ? false : 'run tool/oracles/setup.sh to install HarfBuzz');
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
