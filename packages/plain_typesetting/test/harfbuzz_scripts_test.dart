// Each script's sample lines (test/fixtures/scripts) shaped as HarfBuzz
// 14.6.0 shapes them: the same glyphs in the same visual order, the same
// advances and the same mark offsets, in the subset Noto fonts fonts.txt
// lists (tool/subset_test_fonts.dart makes them). The oracle is a full
// HarfBuzz build (tool/oracles/harfbuzz-native/setup.sh), else harfbuzzjs
// (tool/oracles/setup.sh; built without the vowel constraints, so the
// lines that test them are left to the native oracle); the tests are
// skipped where neither is installed.
@TestOn('vm')
@Tags(['tools'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

const String _shape = 'tool/oracles/harfbuzz/shape.mjs';
const String _native = 'tool/oracles/harfbuzz-native/hb-oracle';
const String _fixtures = 'test/fixtures/scripts';

void main() {
  final ready =
      File(_native).existsSync() ||
      Directory('tool/oracles/harfbuzz/node_modules').existsSync();
  for (final entry in File('$_fixtures/fonts.txt').readAsLinesSync()) {
    if (entry.startsWith('#') || entry.trim().isEmpty) continue;
    final [font, _, files, direction] = [
      for (final f in entry.split('|')) f.trim(),
    ].sublist(0, 4);
    for (final file in files.split(' ')) {
      test('$file in $font shapes as HarfBuzz shapes it', () {
        final path = 'test/fonts/$font';
        final lines = File('$_fixtures/$file')
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            // (Lines of vowel sequences a script prohibits, marked `#!`,
            // need the native oracle.)
            .where((l) => !l.startsWith('#!') || File(_native).existsSync())
            .map((l) => l.startsWith('#!') ? l.substring(2) : l)
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
  if (File(_native).existsSync()) {
    final dir = Directory.systemTemp.createTempSync('harfbuzz_oracle.');
    try {
      final input = File('${dir.path}/lines')
        ..writeAsStringSync('${lines.join('\n')}\n');
      final r = Process.runSync('sh', [
        '-c',
        '"\$0" "\$1" < "${input.path}"',
        _native,
        font,
      ]);
      if (r.exitCode != 0) throw StateError('HarfBuzz: ${r.stderr}');
      return [
        for (final line in (r.stdout as String).trim().split('\n'))
          (jsonDecode(line) as List).cast<Object?>(),
      ];
    } finally {
      dir.deleteSync(recursive: true);
    }
  }
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
