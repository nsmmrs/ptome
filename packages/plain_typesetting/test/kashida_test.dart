// Kashida: justified Arabic lengthened inside its words by tatweel, at
// each word's best-ranked place, before its spaces are widened.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final OpenTypeShaper _naskh = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notonaskharabic-subset.ttf').readAsBytesSync(),
  ),
);

final TextStyle _style = TextStyle(_naskh, 20);

/// The one line of [text], justified to [width] with [kashida] em a word.
Line _line(String text, double width, {double kashida = 0.5}) {
  final lines = const FirstFitLineBreaker().breakLines(
    Paragraph(
      [TextRun(text, _style)],
      rightToLeft: true,
      align: TextAlign.justify,
      alignLast: TextAlign.justify,
      kashida: kashida,
    ),
    (_) => width,
  );
  expect(lines, hasLength(1));
  return lines.single;
}

TextFragment _fragment(Line line) =>
    line.fragments.whereType<TextFragment>().single;

final int _tatweel = _style.shape('\u0640').single.id;

/// The fragment's glyphs' text in logical order, an inserted tatweel as
/// `-`.
String _logical(TextFragment fragment) => [
  for (final glyph in fragment.glyphs.reversed)
    if (glyph.id == _tatweel && glyph.text.isEmpty) '-' else glyph.text,
].join();

double _natural(String text) =>
    _style.widthOf(_style.shape(text, rightToLeft: true));

void main() {
  test('a word is lengthened after its Seen before the spaces widen', () {
    const text = 'كتاب مسجد';
    final line = _line(text, _natural(text) + 4);
    final fragment = _fragment(line);
    // (Rank 2, after the Seen, beats rank 4, before كتاب's final Alef.)
    expect(_logical(fragment), contains('س-'));
    expect(_logical(fragment).replaceAll('-', ''), text);
    expect(fragment.style.wordSpacing, closeTo(0, 1e-6));
    expect(fragment.width, closeTo(_natural(text) + 4, 1e-6));
  });

  test('each word up to its limit, the spaces the rest', () {
    const text = 'كتاب مسجد';
    final line = _line(text, _natural(text) + 20, kashida: 0.25);
    final fragment = _fragment(line);
    // (Both words lengthened, 5 points each, the space the other 10.)
    expect('-'.allMatches(_logical(fragment)).length, greaterThan(1));
    expect(fragment.style.wordSpacing, closeTo(10, 1e-6));
    expect(fragment.width, closeTo(_natural(text) + 20, 1e-6));
  });

  test('a word with no ranked place is not lengthened', () {
    // (Dal, Alef and Reh join nothing after them.)
    const text = 'دار ورد';
    final fragment = _fragment(_line(text, _natural(text) + 6));
    expect(_logical(fragment), isNot(contains('-')));
    expect(fragment.style.wordSpacing, closeTo(6, 1e-6));
  });

  test('Lam-Alef is never divided', () {
    // (Its one place, between Lam and Alef, isn't one.)
    const text = 'لا لا';
    final fragment = _fragment(_line(text, _natural(text) + 6));
    expect(_logical(fragment), isNot(contains('-')));
  });

  test('without kashida only the spaces widen', () {
    const text = 'كتاب مسجد';
    final fragment = _fragment(_line(text, _natural(text) + 4, kashida: 0));
    expect(_logical(fragment), isNot(contains('-')));
    expect(fragment.style.wordSpacing, closeTo(4, 1e-6));
  });
}
