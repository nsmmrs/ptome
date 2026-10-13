// Right-to-left paragraphs: a line's text put in visual order by the
// Unicode Bidirectional Algorithm, right-to-left runs shaped as such,
// the lines set from the right where the paragraph says so.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final OpenTypeShaper _hebrew = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserifhebrew-subset.ttf').readAsBytesSync(),
  ),
);
final OpenTypeShaper _latin = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);

List<Line> _lines(
  List<InlineContent> content, {
  bool rightToLeft = true,
  TextAlign align = TextAlign.right,
  double firstLineIndent = 0,
  double width = 300,
}) => const FirstFitLineBreaker().breakLines(
  Paragraph(
    content,
    rightToLeft: rightToLeft,
    align: align,
    firstLineIndent: firstLineIndent,
  ),
  (_) => width,
);

List<String> _texts(Line line) => [
  for (final fragment in line.fragments)
    if (fragment is TextFragment) fragment.text,
];

String _glyphText(TextFragment fragment) =>
    fragment.glyphs.map((g) => g.text).join();

void main() {
  final hebrew = TextStyle(_hebrew, 12);
  final latin = TextStyle(_latin, 12);

  test('a right-to-left line: its runs in visual order, right to left', () {
    final [line] = _lines([
      TextRun('שלום ', hebrew),
      TextRun('abc', latin),
      TextRun(' עולם', hebrew),
    ]);
    // (The last word leftmost, the Latin run between, the first rightmost.)
    expect(_texts(line), [' עולם', 'abc', 'שלום ']);
    final fragments = line.fragments.cast<TextFragment>();
    // Each right-to-left run's glyphs reversed: its space at its right.
    expect(_glyphText(fragments.first), 'םלוע ');
    expect(_glyphText(fragments[1]), 'abc');
    expect(_glyphText(fragments.last), ' םולש');
    for (var i = 1; i < fragments.length; i++) {
      expect(
        fragments[i].x,
        closeTo(fragments[i - 1].x + fragments[i - 1].width, 1e-9),
      );
    }
  });

  test('one run split where its direction changes', () {
    final [line] = _lines([TextRun('שלום abc עולם', hebrew)]);
    // (The spaces between the Latin and Hebrew words take the
    // paragraph's direction.)
    expect(_texts(line), [' עולם', 'abc', 'שלום ']);
  });

  test('right-aligned from the right edge, the indent at the right', () {
    final [line] = _lines([TextRun('שלום עולם', hebrew)]);
    final last = line.fragments.last;
    expect(last.x + last.width, closeTo(300, 1e-9));
    final [indented] = _lines([
      TextRun('שלום עולם', hebrew),
    ], firstLineIndent: 20);
    final end = indented.fragments.last;
    expect(end.x + end.width, closeTo(280, 1e-9));
    expect(indented.fragments.first.x, greaterThan(100));
  });

  test('a left-to-right paragraph reorders its right-to-left words', () {
    final [line] = _lines(
      [TextRun('see ', latin), TextRun('שלום עולם', hebrew)],
      rightToLeft: false,
      align: TextAlign.left,
    );
    expect(_texts(line), ['see ', 'שלום עולם']);
    expect(line.fragments.first.x, 0);
    expect(_glyphText(line.fragments.last as TextFragment), 'םלוע םולש');
  });

  test('a line shaped in visual order (as a text box draws it)', () {
    String text(List<ShapedGlyph> glyphs) => glyphs.map((g) => g.text).join();
    expect(text(hebrew.shapeBidi('אב גד')), 'דג בא');
    expect(text(hebrew.shapeBidi('אב 12')), '12 בא');
    expect(text(hebrew.shapeBidi('אב 12', rightToLeft: true)), '12 בא');
    // (A left-to-right line keeps its Latin words first.)
    expect(text(latin.shapeBidi('ab ')), 'ab ');
    expect(hebrew.shapeBidi('ab cd').map((g) => g.id), [
      for (final g in hebrew.shape('ab cd')) g.id,
    ]);
  });

  test('a left-to-right line of Latin text is untouched', () {
    final [line] = _lines(
      [TextRun('plain text', latin)],
      rightToLeft: false,
      align: TextAlign.left,
    );
    expect(_texts(line), ['plain text']);
  });
}
