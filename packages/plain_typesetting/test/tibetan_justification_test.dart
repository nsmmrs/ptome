// Tibetan justified as r12a's Tibetan notes (which tlreq points to)
// describe printed practice: the room spread between all its characters
// alike, or, with tsheg padding, a line ending with a tsheg filled out
// with more tshegs first.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

final OpenTypeShaper _tibetan = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoseriftibetan-subset.ttf').readAsBytesSync(),
  ),
);

final TextStyle _style = TextStyle(_tibetan, 20);

Line _line(String text, double extra, {bool padding = false}) {
  final natural = _style.widthOf(_style.shape(text));
  return const KnuthPlassLineBreaker()
      .breakLines(
        Paragraph(
          [TextRun(text, _style)],
          align: TextAlign.justify,
          alignLast: TextAlign.justify,
          tshegPadding: padding,
        ),
        (_) => natural + extra,
      )
      .single;
}

List<ShapedGlyph> _glyphs(Line line) => [
  for (final f in line.fragments.whereType<TextFragment>()) ...f.glyphs,
];

void main() {
  const text = 'བོད་སྐད་ཀྲ་ཤིས་';

  test('the room spread between all its characters alike', () {
    final plain = _style.shape(text);
    final glyphs = _glyphs(_line(text, 12));
    final added = [
      for (final (i, g) in glyphs.indexed)
        if (g.kerning != plain[i].kerning) g.kerning - plain[i].kerning,
    ];
    expect(added.length, greaterThan(4));
    expect(added.toSet().length, 1);
    final fragment = _line(text, 12).fragments.single;
    expect(fragment.width, closeTo(_style.widthOf(plain) + 12, 1e-6));
  });

  test('tsheg padding: a line ending with a tsheg filled out with tshegs '
      'standing for no text', () {
    final tsheg = _style.widthOf(_style.shape('་'));
    final plain = _style.shape(text);
    final glyphs = _glyphs(_line(text, tsheg * 3 + 1, padding: true));
    expect(glyphs.length, plain.length + 3);
    final id = _style.shape('\u0f0b').single.id;
    for (final g in glyphs.skip(plain.length)) {
      expect((g.id, g.text), (id, ''));
    }
    // (A line ending otherwise, with a shad: spread between characters.)
    const shad = '\u0f56\u0f7c\u0f51\u0f0b\u0f66\u0f90\u0f51\u0f0d';
    expect(
      _glyphs(_line(shad, tsheg * 3, padding: true)).length,
      _style.shape(shad).length,
    );
  });
}
