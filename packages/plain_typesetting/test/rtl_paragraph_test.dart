// Right-to-left paragraphs: a line's text put in visual order by the
// Unicode Bidirectional Algorithm, right-to-left runs shaped as such,
// the lines set from the right where the paragraph says so.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

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

  test('a run with no text but an anchor keeps its place', () {
    // (A footnote reference's anchor after a right-to-left word: lost, its
    // note never set, while the line was reordered.)
    for (final rightToLeft in [true, false]) {
      final [line] = _lines([
        TextRun('שלום', hebrew),
        TextRun('', hebrew, anchor: 'ref'),
        TextRun('[1]', latin),
        TextRun(' עולם', hebrew),
      ], rightToLeft: rightToLeft);
      final anchored = [
        for (final fragment in line.fragments)
          if (fragment case TextFragment(:final run) when run.anchor != null)
            fragment,
      ];
      expect(anchored, hasLength(1), reason: 'rightToLeft: $rightToLeft');
      // (Where the reference starts, its opening bracket: beside it.)
      final digit = line.fragments.cast<TextFragment>().firstWhere(
        (f) => f.text.contains('['),
      );
      expect(
        [
          digit.x,
          digit.x + digit.width,
        ].any((edge) => (edge - anchored.single.x).abs() < 1e-9),
        isTrue,
      );
    }
  });

  test('its anchors in reading order, the fragments in visual order', () {
    final [line] = _lines([
      TextRun('אחד', hebrew, anchor: 'first'),
      TextRun(' שתיים', hebrew, anchor: 'second'),
      TextRun(' שלוש', hebrew, anchor: 'third'),
    ]);
    String? anchorOf(LineFragment f) => (f as TextFragment).run.anchor;
    expect(line.fragments.map(anchorOf), ['third', 'second', 'first']);
    expect(line.fragmentsInReadingOrder.map(anchorOf), [
      'first',
      'second',
      'third',
    ]);
    // (Placed, they're reported as read: a footnote's notes in order.)
    final placed = ParagraphContent(
      Paragraph([
        TextRun('אחד', hebrew, anchor: 'first'),
        TextRun(' שתיים', hebrew, anchor: 'second'),
      ], rightToLeft: true),
    ).placeLines(300, 1);
    expect(placed.anchors.map((a) => a.$1), ['first', 'second']);
    final [plain] = _lines([TextRun('abc', latin)], rightToLeft: false);
    expect(plain.readingOrder, isNull);
  });

  test('each run tells the canvas its text as drawn', () {
    final [line] = _lines([
      TextRun('שלום ', hebrew),
      TextRun('abc', latin),
      TextRun('(1)', latin, artifact: true),
    ]);
    final canvas = RecordingCanvas();
    line.paint(canvas, 0, 100);
    // (A right-to-left run's characters reversed, as its glyphs are drawn;
    // decoration none.)
    expect(canvas.drawnTexts, contains(' םולש'));
    expect(canvas.drawnTexts, contains('abc'));
    expect(canvas.drawnTexts, contains(null));
  });
}
