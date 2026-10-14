// BCP 47 language tags to OpenType language system tags, as HarfBuzz maps
// them: every language and rule of its tables, with scripts, regions,
// extended languages, variants and private use, against the native oracle.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/src/shaping/language_tags.dart';
import 'package:plain_typesetting/src/shaping/shape.dart' show shapeText;
import 'package:test/test.dart';

const String _native = 'tool/oracles/harfbuzz-native/hb-oracle';

/// Tags to try: the generated tables' languages and rules, alone and with
/// scripts, regions and variants.
List<String> _corpus() {
  final generated = File('lib/src/shaping/language_tags.g.dart')
      .readAsStringSync();
  final keys = {
    for (final m in RegExp(
      "^  '([a-z]{2,3})':",
      multiLine: true,
    ).allMatches(generated))
      m[1]!,
  };
  final specs = {
    for (final m in RegExp(
      r"_LanguageRule\.\w+\('([^']+)'(?:, '([^']+)')?",
    ).allMatches(generated)) ...[m[1]!, if (m[2] != null) m[2]!],
  };
  const scripts = ['', '-Hans', '-Hant', '-Latn', '-Cyrl', '-Arab', '-Deva'];
  const regions = ['', '-CN', '-TW', '-HK', '-MO', '-SG', '-US', '-RS'];
  return {
    for (final key in keys) ...[
      key,
      for (final s in scripts)
        for (final r in regions) '$key$s$r',
    ],
    for (final spec in specs) ...[
      spec,
      'und$spec',
      'zh$spec',
      '$spec-x-private',
    ],
    'zh-yue',
    'zh-cmn-Hant',
    'zh-min-nan',
    'art-lojban',
    'el-polyton',
    'hy-arevmda',
    'en-x-hbotabcd',
    'x-hbot-41424344',
    'sr-Latn-RS',
    'xyz',
    'xyz-Latn',
    'q',
    'abcdefgh',
    'en_US',
    'ZH-HANT-hk',
    'i-klingon',
    'sgn-BE-FR',
    'zh-Latn-pinyin',
    'ja-Kana',
    'und',
    'x-foo',
  }.toList();
}

void main() {
  test('everyday tags', () {
    expect(openTypeLanguageTags('ja'), ['JAN ']);
    expect(openTypeLanguageTags('zh-Hans'), ['ZHS ']);
    expect(openTypeLanguageTags('zh-Hant'), ['ZHT ']);
    expect(openTypeLanguageTags('zh-HK'), ['ZHH ']);
    expect(openTypeLanguageTags('sr-Latn'), ['SRB ']);
    expect(openTypeLanguageTags('mr'), ['MAR ']);
    expect(openTypeLanguageTags('ur'), ['URD ']);
    expect(openTypeLanguageTags('tr'), ['TRK ']);
    expect(openTypeLanguageTags(''), isEmpty);
  });

  test("the language's system changes the glyphs", () {
    final cjk = OpenTypeFont.parse(
      File('test/fonts/notosanscjk-jp-subset.otf').readAsBytesSync(),
    );
    List<int> glyphs(String language) => [
      for (final g in shapeText(
        cjk,
        '直骨今',
        rightToLeft: false,
        language: language,
      ))
        g.glyph,
    ];
    expect(glyphs('zh-Hans'), isNot(glyphs('ja')));
    expect(glyphs('zh-HK'), isNot(glyphs('zh-Hans')));
    // (No language, or one the font has no system for: the default.)
    expect(glyphs('en'), glyphs('ja'));
  });

  test('every table entry and rule maps as HarfBuzz maps it', () {
    final corpus = _corpus();
    final r = Process.runSync('sh', [
      '-c',
      r'printf "%s\n" "$@" | "$0" --language-tags',
      _native,
      ...corpus,
    ]);
    final theirs = (r.stdout as String).split('\n');
    final differ = <String>[];
    for (final (i, tag) in corpus.indexed) {
      final ours = [for (final t in openTypeLanguageTags(tag)) '[$t]']
          .join(' ');
      if (ours != theirs[i]) {
        differ.add('$tag: ours $ours, HarfBuzz ${theirs[i]}');
      }
    }
    expect(corpus.length, greaterThan(5000));
    expect(differ, isEmpty, reason: differ.take(10).join('\n'));
  }, skip: File(_native).existsSync() ? false : 'needs the native oracle');
}
