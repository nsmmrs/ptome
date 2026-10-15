// Line-breaking strictness (CSS Text 3's line-break, 5.3): the rules it
// tailors UAX #14 with, against ICU 78.3's line break iterator with the
// `lb` keyword (`ja@lb=strict`, `normal`, `loose`), whose answers are
// frozen in test/frozen/line_break_strictness.json
// (test/support/frozen.dart; FROZEN=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'support/frozen.dart';

const String _oracle = 'tool/oracles/icu/icubreak';

/// The oracle, which its answers depend on.
const String _version = 'ICU 78.3';

late final Frozen _frozen;

/// ICU's breaks of each of [texts] in [locale]: a line of offsets each.
List<String> _icu(String locale, List<String> texts) => _frozen
    .answer(
      '$locale: ${texts.length} texts',
      inputs: [_version, locale, ...texts],
      oracle: () {
        final dir = Directory.systemTemp.createTempSync('lb.');
        try {
          final input = File('${dir.path}/in.txt')
            ..writeAsStringSync('${texts.join('\n')}\n');
          return Process.runSync('sh', [
                '-c',
                '"$_oracle" "$locale" < "${input.path}"',
              ]).stdout
              as String;
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    )
    .trim()
    .split('\n');

/// Every rule's case, in Japanese text.
const List<String> _texts = [
  '東京ょうょっとカーテン々ゝです。日本〜東京゠アです。',
  '……と‥‥あ漢‐字–字。',
  '漢・字：漢；字！漢？字‼漢100％と℃と￥100と€100。',
  'ニャーンと言った。',
  'abc def ghi',
];

List<int> _breaks(
  String text,
  LineBreakStrictness strictness, {
  bool cj = true,
}) {
  final o = lineBreakOffsets(
    text,
    strictness: strictness,
    chineseOrJapanese: cj,
  );
  return [for (var i = 0; i < o.length; i++) o.offsetAt(i)];
}

void main() {
  _frozen = Frozen('line_break_strictness');
  test('strict is UAX #14: no line starts with small kana', () {
    expect(_breaks('ニャーン', LineBreakStrictness.strict), [3, 4]);
    expect(_breaks('ニャーン', LineBreakStrictness.strict), [
      for (final b in lineBreaks('ニャーン')) b.offset,
    ]);
  });

  test('normal: 〜 and ゠ may start a line, in Chinese and Japanese', () {
    expect(_breaks('東〜京', LineBreakStrictness.normal), [1, 2, 3]);
    expect(_breaks('東〜京', LineBreakStrictness.strict), [2, 3]);
    expect(_breaks('東〜京', LineBreakStrictness.normal, cj: false), [2, 3]);
    expect(_breaks('ニャーン', LineBreakStrictness.normal), [3, 4]);
  });

  test('loose: small kana, iteration marks, inseparables, hyphens; '
      'centered marks and wide affixes in Chinese and Japanese', () {
    expect(_breaks('ニャーン', LineBreakStrictness.loose), [1, 2, 3, 4]);
    expect(_breaks('時々', LineBreakStrictness.loose), [1, 2]);
    expect(_breaks('……', LineBreakStrictness.loose), [1, 2]);
    expect(_breaks('漢‐字', LineBreakStrictness.loose), [1, 2, 3]);
    expect(_breaks('漢！字', LineBreakStrictness.loose), [1, 2, 3]);
    expect(_breaks('漢！字', LineBreakStrictness.loose, cj: false), [2, 3]);
    expect(_breaks('1％', LineBreakStrictness.loose), [1, 2]);
    expect(_breaks('￥1', LineBreakStrictness.loose), [1, 2]);
  });

  test('anywhere: between any two characters, not within a cluster', () {
    expect(_breaks('abc', LineBreakStrictness.anywhere), [1, 2, 3]);
    expect(_breaks('éx', LineBreakStrictness.anywhere), [2, 3]);
    expect(_breaks('👍🏽a', LineBreakStrictness.anywhere), [4, 5]);
    expect(_breaks('🇯🇵a', LineBreakStrictness.anywhere), [4, 5]);
  });

  test(
    "curly quotes in Chinese break as UAX #14's East Asian rule (LB19a)",
    () {
      // (A break before “ and after ”, between Han characters; none inside.)
      const text = '中文“引号”中文';
      final ours = [for (final b in lineBreaks(text)) b.offset];
      expect(ours, containsAll([2, 6]));
      expect(ours, isNot(contains(3)));
      expect(ours, isNot(contains(5)));
      expect(
        ours,
        _icu('zh', [text]).single.split(' ').map(int.parse).skip(1).toList(),
      );
    },
  );

  test('as ICU 78.3 breaks Japanese, strict, normal and loose', () {
    for (final (strictness, keyword) in [
      (LineBreakStrictness.strict, 'strict'),
      (LineBreakStrictness.normal, 'normal'),
      (LineBreakStrictness.loose, 'loose'),
    ]) {
      final theirs = [
        for (final line in _icu('ja@lb=$keyword', _texts))
          {for (final n in line.split(' ')) int.parse(n)}..remove(0),
      ];
      for (final (i, text) in _texts.indexed) {
        final ours = _breaks(text, strictness).toSet();
        if (strictness == LineBreakStrictness.normal) {
          // (ICU's normal also breaks before small kana and the prolonged
          // sound mark, class CJ, which CSS Text 3 keeps for loose.)
          final runes = text.codeUnits;
          final onlyIcu = theirs[i].difference(ours);
          expect(
            onlyIcu.every(
              (at) => lineBreakClass(runes[at]) == LineBreakClass.cj,
            ),
            isTrue,
            reason: '$keyword "$text": $onlyIcu',
          );
          expect(ours.difference(theirs[i]), isEmpty, reason: text);
        } else {
          expect(ours, theirs[i], reason: '$keyword "$text"');
        }
      }
    }
  });
}
