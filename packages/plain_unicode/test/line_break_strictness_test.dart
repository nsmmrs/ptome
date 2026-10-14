// Line-breaking strictness (CSS Text 3's line-break, 5.3): the rules it
// tailors UAX #14 with, against ICU 78.3's line break iterator with the
// `lb` keyword (`ja@lb=strict`, `normal`, `loose`) where ICU is built.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

const String _oracle = 'tool/oracles/icu/icubreak';

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
      if (File(_oracle).existsSync()) {
        final r = Process.runSync('sh', [
          '-c',
          r'printf "%s\n" "$1" | "$0" zh',
          _oracle,
          text,
        ]);
        expect(
          ours,
          '${r.stdout}'.trim().split(' ').map(int.parse).skip(1).toList(),
        );
      }
    },
  );

  test(
    'as ICU 78.3 breaks Japanese, strict, normal and loose',
    () {
      for (final (strictness, keyword) in [
        (LineBreakStrictness.strict, 'strict'),
        (LineBreakStrictness.normal, 'normal'),
        (LineBreakStrictness.loose, 'loose'),
      ]) {
        final dir = Directory.systemTemp.createTempSync('lb.');
        addTearDown(() => dir.deleteSync(recursive: true));
        final input = File('${dir.path}/in.txt')
          ..writeAsStringSync('${_texts.join('\n')}\n');
        final r = Process.runSync('sh', [
          '-c',
          '"$_oracle" "ja@lb=$keyword" < "${input.path}"',
        ]);
        final theirs = [
          for (final line in '${r.stdout}'.trim().split('\n'))
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
    },
    skip: File(_oracle).existsSync() ? false : 'run tool/oracles/icu/setup.sh',
  );
}
