// Each script's sample lines (test/fixtures/scripts) shaped as HarfBuzz
// shapes them (harfbuzzjs, in tool/oracles/harfbuzz, installed by
// tool/oracles/setup.sh; skipped where it isn't): the same glyphs in the
// same visual order, the same advances and the same mark offsets, in the
// subset Noto fonts fonts.txt lists (tool/subset_test_fonts.dart makes
// them).
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

const String _shape = 'tool/oracles/harfbuzz/shape.mjs';
const String _fixtures = 'test/fixtures/scripts';

void main() {
  final ready = Directory('tool/oracles/harfbuzz/node_modules').existsSync();
  for (final entry in File('$_fixtures/fonts.txt').readAsLinesSync()) {
    if (entry.startsWith('#') || entry.trim().isEmpty) continue;
    final [font, _, files, direction] = [
      for (final f in entry.split('|')) f.trim(),
    ];
    for (final file in files.split(' ')) {
      test('$file in $font shapes as HarfBuzz shapes it', () {
        final path = 'test/fonts/$font';
        final lines = File('$_fixtures/$file')
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .toList();
        final differ = shapeDifferences(
          path,
          lines,
          rightToLeft: direction == 'rtl',
        );
        expect(differ, isEmpty, reason: differ.take(3).join('\n'));
      }, skip: ready ? false : 'run tool/oracles/setup.sh to install HarfBuzz');
    }
  }
}

/// The lines of [lines] the font at [path] doesn't shape as HarfBuzz
/// does, each with both glyph lists.
List<String> shapeDifferences(
  String path,
  List<String> lines, {
  required bool rightToLeft,
}) {
  final font = OpenTypeShaper(OpenTypeFont.parse(File(path).readAsBytesSync()));
  final upem = font.font.unitsPerEm;
  final theirs = harfbuzz(path, lines);
  final differ = <String>[];
  for (final (i, line) in lines.indexed) {
    int units(double v) => (v * upem / 1000).round();
    final ours = [
      for (final g in font.shape(
        line,
        rightToLeft: rightToLeft,
        ligatures: true,
      ))
        [
          g.id,
          units(g.advance + g.kerning),
          units(g.xOffset),
          units(g.yOffset),
        ],
    ];
    final expected = [
      for (final g in theirs[i].cast<List<Object?>>()) [g[0], g[2], g[3], g[4]],
    ];
    if (jsonEncode(ours) != jsonEncode(expected)) {
      var at = 0;
      while (at < ours.length &&
          at < expected.length &&
          jsonEncode(ours[at]) == jsonEncode(expected[at])) {
        at++;
      }
      differ.add(
        '$line\n    from glyph $at:\n'
        '    ours:     ${ours.skip(at).take(8).toList()}\n'
        '    HarfBuzz: ${expected.skip(at).take(8).toList()}',
      );
    }
  }
  return differ;
}

/// HarfBuzz's [glyph, cluster, advance, x offset, y offset] glyphs of each
/// of [lines] in [font], in visual order.
List<List<Object?>> harfbuzz(String font, List<String> lines) {
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
