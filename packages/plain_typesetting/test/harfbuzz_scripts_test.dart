// Each script's sample lines (test/fixtures/scripts) shaped as HarfBuzz
// 14.6.0 shapes them: the same glyphs in the same visual order, the same
// advances and the same mark offsets, in the subset Noto fonts fonts.txt
// lists (tool/subset_test_fonts.dart makes them). The oracle is a full
// HarfBuzz build (tool/oracles/harfbuzz-native/setup.sh); its answers are
// recorded in test/oracles/harfbuzz_scripts.json (test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_typesetting/src/shaping/shape.dart' show shapeText;
import 'package:test/test.dart';

import 'support/oracles.dart';

const String _native = 'tool/oracles/harfbuzz-native/hb-oracle';

/// The oracle, which its answers depend on.
const String _oracle = 'HarfBuzz 14.6.0';

late final Oracle _recorded;
const String _fixtures = 'test/fixtures/scripts';

void main() {
  _recorded = Oracle('harfbuzz_scripts');
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
            // (Lines of vowel sequences a script prohibits are marked
            // `#!`.)
            .map((l) => l.startsWith('#!') ? l.substring(2) : l)
            .toList();
        final differ = shapeDifferences(
          '$file in $font',
          path,
          lines,
          rightToLeft: direction == 'rtl',
        );
        expect(differ, isEmpty, reason: differ.take(3).join('\n'));
      });
    }
  }
  // Top to bottom (HarfBuzz's TTB direction): the vertical forms, the
  // vertical advances and origins (VORG; vmtx and TrueType outlines; the
  // glyph centered without them), the marks attached across.
  for (final entry in File('$_fixtures/fonts.txt').readAsLinesSync()) {
    if (entry.startsWith('#') || entry.trim().isEmpty) continue;
    final [font, _, files, direction] = [
      for (final f in entry.split('|')) f.trim(),
    ].sublist(0, 4);
    if (direction != 'ltr') continue;
    test('${files.replaceAll(' ', ', ')} in $font top to bottom', () {
      final path = 'test/fonts/$font';
      final parsed = OpenTypeFont.parse(File(path).readAsBytesSync());
      final lines = [
        for (final file in files.split(' '))
          ...File('$_fixtures/$file')
              .readAsLinesSync()
              .where((l) => l.isNotEmpty && !l.startsWith('#')),
      ];
      final theirs = harfbuzz(
        '$files in $font top to bottom',
        path,
        lines,
        features: {'--ttb'},
      );
      final differ = <String>[];
      for (final (i, line) in lines.indexed) {
        final ours = [
          for (final g in shapeText(
            parsed,
            line,
            rightToLeft: false,
            vertical: true,
          ))
            [g.glyph, -g.advance, g.xOffset, g.yOffset],
        ];
        final expected = [
          for (final g in theirs[i].cast<List<Object?>>())
            [g[0], g[2], g[3], g[4]],
        ];
        if (jsonEncode(ours) != jsonEncode(expected)) {
          differ.add('$line\n    ours:     $ours\n    HarfBuzz: $expected');
        }
      }
      expect(differ, isEmpty, reason: differ.take(2).join('\n'));
    });
  }

  // The language's systems (its `locl` and other features): CJK glyphs
  // by region, Serbian and Macedonian Cyrillic, Marathi and Nepali
  // Devanagari, Urdu and Sindhi digits.
  for (final (font, file, direction, languages) in const [
    (
      'notosanscjk-jp-subset.otf',
      'japanese.txt',
      'ltr',
      ['ja', 'zh-Hans', 'zh-Hant', 'zh-HK', 'zh-TW', 'ko'],
    ),
    ('notoserif-scripts.ttf', 'cyrillic.txt', 'ltr', ['ru', 'sr', 'mk', 'bg']),
    (
      'notosansdevanagari-subset.ttf',
      'devanagari.txt',
      'ltr',
      ['hi', 'mr', 'ne', 'sa'],
    ),
    (
      'notonaskharabic-persian-urdu.ttf',
      'urdu.txt',
      'rtl',
      ['ur', 'fa', 'sd', 'ar'],
    ),
  ]) {
    test('$file in $font by language (${languages.join(', ')})', () {
      final path = 'test/fonts/$font';
      final parsed = OpenTypeFont.parse(File(path).readAsBytesSync());
      final lines = File('$_fixtures/$file')
          .readAsLinesSync()
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      final differ = <String>[];
      for (final language in languages) {
        final theirs = harfbuzz(
          '$file in $font in $language',
          path,
          lines,
          features: {'--language=$language'},
        );
        for (final (i, line) in lines.indexed) {
          final ours = [
            for (final g in shapeText(
              parsed,
              line,
              rightToLeft: direction == 'rtl',
              language: language,
            ))
              [g.glyph, g.advance, g.xOffset, g.yOffset],
          ];
          final expected = [
            for (final g in theirs[i].cast<List<Object?>>())
              [g[0], g[2], g[3], g[4]],
          ];
          if (jsonEncode(ours) != jsonEncode(expected)) {
            differ.add(
              '$language: $line\n  ours:     $ours\n  HarfBuzz: $expected',
            );
          }
        }
      }
      expect(differ, isEmpty, reason: differ.take(2).join('\n'));
    });
  }

  // East Asian features a typesetter turns on: punctuation set half wide
  // between others (chws) or always (halt), proportional (palt), and
  // the vertical forms (vert, vrt2).
  for (final feature in const ['chws', 'halt', 'palt', 'vert', 'vrt2']) {
    test('japanese.txt and chinese.txt with $feature shape as HarfBuzz', () {
      final lines = [
        for (final file in const ['japanese.txt', 'chinese.txt'])
          ...File('$_fixtures/$file')
              .readAsLinesSync()
              .where((l) => l.isNotEmpty),
      ];
      final differ = shapeDifferences(
        'japanese.txt and chinese.txt with $feature',
        'test/fonts/notosanscjk-jp-subset.otf',
        lines,
        rightToLeft: false,
        features: {feature},
      );
      expect(differ, isEmpty, reason: differ.take(3).join('\n'));
    });
  }
}

/// The lines of [lines] the font at [path] doesn't shape as HarfBuzz
/// does, each with both glyph lists.
List<String> shapeDifferences(
  String key,
  String path,
  List<String> lines, {
  required bool rightToLeft,
  Set<String> features = const {},
}) {
  final font = OpenTypeShaper(OpenTypeFont.parse(File(path).readAsBytesSync()));
  final upem = font.font.unitsPerEm;
  final theirs = harfbuzz(key, path, lines, features: features);
  final differ = <String>[];
  for (final (i, line) in lines.indexed) {
    int units(double v) => (v * upem / 1000).round();
    final ours = [
      for (final g in font.shape(
        line,
        rightToLeft: rightToLeft,
        ligatures: true,
        features: features,
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
/// of [lines] in [font], in visual order, as recorded for [key].
List<List<Object?>> harfbuzz(
  String key,
  String font,
  List<String> lines, {
  Set<String> features = const {},
}) => _recorded
    .json<List<Object?>>(
      key,
      inputs: [
        _oracle,
        File(font).readAsBytesSync(),
        jsonEncode([features.toList(), lines]),
      ],
      oracle: () => _harfbuzz(font, lines, features),
    )
    .cast<List<Object?>>();

/// [harfbuzz]'s answer from the native oracle.
List<List<Object?>> _harfbuzz(
  String font,
  List<String> lines,
  Set<String> features,
) {
  final dir = Directory.systemTemp.createTempSync('harfbuzz_oracle.');
  try {
    final input = File('${dir.path}/lines')
      ..writeAsStringSync('${lines.join('\n')}\n');
    final r = Process.runSync('sh', [
      '-c',
      '"\$0" "\$@" < "${input.path}"',
      _native,
      font,
      ...features,
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
