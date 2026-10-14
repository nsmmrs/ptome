/// Text shaped by a font's OpenType layout tables in full, as HarfBuzz
/// 14.6 shapes it (`shaping/`): the scripts whose letters change with
/// their neighbours or reorder (Arabic, Syriac, the Indic scripts, ...),
/// text with marks the font places, right-to-left runs. Text that needs
/// none of it takes the font's simple path (its glyphs, ligatures and
/// kerning).
library;

import 'package:plain_fonts/plain_fonts.dart' show OpenTypeFont;
import 'package:plain_typesetting/src/font.dart';
import 'package:plain_typesetting/src/shaping/shape.dart';
import 'package:plain_unicode/plain_unicode.dart';

/// Whether [text] needs the font's layout tables in full: it has a mark,
/// a default ignorable (a joiner), or a character of a script other than
/// Latin, Greek and Cyrillic (whose text the simple path sets, as
/// asciidoctor-pdf's Prawn does; the others take the features HarfBuzz
/// applies, contextual ones included).
bool needsComplexShaping(String text) {
  for (final rune in text.runes) {
    if (rune < 0x0300) continue;
    if (isMark(rune) || isDefaultIgnorable(rune)) return true;
    switch (scriptOf(rune)) {
      case 'Zyyy' || 'Zinh' || 'Zzzz' || 'Latn' || 'Grek' || 'Cyrl':
        continue;
    }
    return true;
  }
  return false;
}

/// Whether [text] has letters of the right-to-left blocks (Hebrew to
/// Arabic Extended, the Hebrew and Arabic presentation forms).
bool hasRightToLeftLetters(String text) {
  for (final unit in text.codeUnits) {
    if (unit >= 0x0590 && unit <= 0x08ff) return true;
    if (unit >= 0xfb1d && unit <= 0xfeff) return true;
  }
  return false;
}

/// [text] in [shaper]'s font as HarfBuzz shapes it, in visual order,
/// in 1000ths of the em.
List<ShapedGlyph> shapeComplex(
  OpenTypeShaper shaper,
  String text, {
  required bool kerning,
  required bool ligatures,
  required Set<String> features,
  required bool rightToLeft,
}) => [
  for (final g in shapeText(
    shaper.font,
    text,
    rightToLeft: rightToLeft,
    kerning: kerning,
    ligatures: ligatures,
    features: features,
  ))
    ShapedGlyph.positioned(
      g.glyph,
      g.text,
      shaper.scale(g.advance),
      xOffset: shaper.scale(g.xOffset),
      yOffset: shaper.scale(g.yOffset),
    ),
];

/// [text] in [font] set top to bottom as HarfBuzz shapes it (its `vert`
/// forms, its vertical advances and origins), each glyph [ShapedGlyph.
/// upright], in 1000ths of the em.
List<ShapedGlyph> shapeUpright(
  OpenTypeFont font,
  String text, {
  bool kerning = true,
  Set<String> features = const {},
}) {
  double scale(int units) => units * 1000 / font.unitsPerEm;
  return [
    for (final g in shapeText(
      font,
      text,
      rightToLeft: false,
      vertical: true,
      kerning: kerning,
      features: features,
    ))
      ShapedGlyph.positioned(
        g.glyph,
        g.text,
        scale(g.advance),
        xOffset: scale(g.xOffset),
        yOffset: scale(g.yOffset),
        upright: true,
      ),
  ];
}
