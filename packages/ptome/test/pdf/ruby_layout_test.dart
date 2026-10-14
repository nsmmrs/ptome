// Ruby laid out as JLREQ 3.3 and CLREQ have it: a shorter reading spread
// over its base (JIS X 4051's 1:2:1, no more than a reading character
// from each end), a longer one hanging over the kana beside it but not
// the Han characters, the rest made up between the base's characters;
// Bopomofo in a column at its character's right.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/ruby.dart';
import 'package:test/test.dart';

/// Noto Sans CJK, subset: kana and some Han characters, all of them a
/// full em wide (as the characters it lacks are, by its .notdef).
final TrueTypeFont _face = TrueTypeFont(
  'JP',
  'normal',
  EmbeddedFont.parse(
    File('../plain_typesetting/test/fonts/notosanscjk-jp-subset.otf')
        .readAsBytesSync(),
  ),
);

/// The x of each piece of [box] of [text] at [size].
List<double> _at(RubyBox box, String text, double size) => [
  for (final (t, s, x, _) in box.pieces)
    if (t == text && s == size) x,
];

void main() {
  const size = 20.0;

  test('a shorter kana reading spread 1:2:1 over a group base', () {
    // (Three characters, 60 points; a reading of two, 20: gaps of 20,
    // 10 at each end.)
    final box = InlineRuby([('日本書', 'にほ')], base: '日本書').at(_face, size);
    expect(box.width, 60);
    expect(_at(box, 'に', 10), [10]);
    expect(_at(box, 'ほ', 10), [40]);
  });

  test('no more than a reading character from each end', () {
    // (Four characters, 80; two reading characters, 20: 10 from each
    // end, the rest between them.)
    final box = InlineRuby([('日本書字', 'にほ')], base: '日本書字').at(_face, size);
    expect(_at(box, 'に', 10), [10]);
    expect(_at(box, 'ほ', 10), [60]);
  });

  test('a longer reading hangs over kana, not Han characters', () {
    // (字, 20; a reading of five characters, 50: 15 too long each side.)
    final ruby = InlineRuby([('字', 'いかがきく')], base: '字');
    final beside = ruby.at(
      _face,
      size,
      before: rubyOverhang('の'.runes.single, before: true, size: size),
      after: rubyOverhang('に'.runes.single, before: false, size: size),
    );
    expect(beside.width, 30);
    expect(beside.startOverhang, 10);
    expect(beside.endOverhang, 10);
    expect(_at(beside, '字', size), [5]);
    expect(_at(beside, 'いかがきく', 10), [-10]);
    final among = ruby.at(
      _face,
      size,
      before: rubyOverhang('日'.runes.single, before: true, size: size),
      after: rubyOverhang('本'.runes.single, before: false, size: size),
    );
    expect(among.width, 50);
    expect(among.startOverhang, 0);
    expect(_at(among, '字', size), [15]);
  });

  test("a group's base spread under a longer reading", () {
    // (日本, 40; six reading characters, 60: 10 between them, 5 at each
    // end.)
    final box = InlineRuby([('日本', 'にほんしょ')], base: '日本').at(_face, size);
    final reading = 5 * _face.widthOf('に', 10);
    final gap = (reading - 40) / 2;
    expect(_at(box, '日', size), [gap / 2]);
    expect(_at(box, '本', size), [gap / 2 + 20 + gap]);
  });

  test('what a reading may hang over (JLREQ 3.3.8)', () {
    double over(String c, {bool before = true}) =>
        rubyOverhang(c.runes.single, before: before, size: size);
    expect(over('の'), 10);
    expect(over('カ'), 10);
    expect(over('ー'), 10);
    expect(over('ょ'), 10);
    expect(over('・'), 10);
    expect(over('日'), 0);
    expect(over('a'), 0);
    expect(over('」'), 10);
    expect(over('」', before: false), 0);
    expect(over('「', before: false), 10);
    expect(over('「'), 0);
    expect(over('、'), 10);
    expect(rubyOverhang(null, before: true, size: size), 0);
  });

  test('Bopomofo in a column at the right of its character (CLREQ)', () {
    final box = InlineRuby([
      ('字', 'ㄓㄨˋ'),
    ], base: '字').at(_face, size, zhuyin: true);
    // (The character, then a column half its width.)
    expect(box.width, 30);
    final symbols = [
      for (final (t, s, x, y) in box.pieces)
        if (s == 6) (t, x, y),
    ];
    final [(_, xA, yA), (_, xB, yB), (tone, xTone, yTone)] = symbols;
    expect(tone, 'ˋ');
    // (Stacked down the column, the tone at the right of the last symbol,
    // its middle level with that symbol's top.)
    expect(xA, closeTo(xB, 1e-9));
    expect(yA - yB, closeTo(6, 1e-9));
    expect(xTone, closeTo(26, 1e-9));
    expect(yTone, closeTo(yB + 3, 1e-9));
    expect(isBopomofo('ㄓㄨˋ'), isTrue);
    expect(isBopomofo('かな'), isFalse);
    // (Not in vertical text: set as a reading there.)
    final reading = InlineRuby([('字', 'ㄓㄨˋ')], base: '字').at(_face, size);
    expect(_at(reading, 'ㄓㄨˋ', 10), hasLength(1));
  });
}
