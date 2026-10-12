// Grapheme clusters kept whole: in font fallback (a base and its mark in
// one font) and where a word too wide for its line is split.
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/recording.dart';

final OpenTypeShaper _serif = OpenTypeShaper(
  OpenTypeFont.parse(
    File('test/fonts/notoserif-regular-latin.ttf').readAsBytesSync(),
  ),
);

/// [_serif] named apart, claiming some characters more ([extra]) and
/// some fewer ([missing]).
final class _Without implements Font {
  new(this.name, this.missing, {this.extra = const {}});

  @override
  final String name;

  final Set<int> missing;

  final Set<int> extra;

  @override
  bool covers(int codePoint) =>
      !missing.contains(codePoint) &&
      (extra.contains(codePoint) || _serif.covers(codePoint));

  @override
  double get ascender => _serif.ascender;
  @override
  double get descender => _serif.descender;
  @override
  double get lineGap => _serif.lineGap;
  @override
  double get capHeight => _serif.capHeight;
  @override
  double get xHeight => _serif.xHeight;
  @override
  double get underlinePosition => _serif.underlinePosition;
  @override
  double get underlineThickness => _serif.underlineThickness;
  @override
  List<ShapedGlyph> shape(
    String text, {
    bool kerning = true,
    bool ligatures = false,
    Set<String> features = const {},
  }) => _serif.shape(
    text,
    kerning: kerning,
    ligatures: ligatures,
    features: features,
  );
  @override
  double widthOf(String text, double size, {bool kerning = true}) =>
      _serif.widthOf(text, size, kerning: kerning);
}

void main() {
  test('a base and its combining mark go to one font', () {
    // The text's font lacks the combining acute; the fallback has both:
    // "é" (e and U+0301) is set in the fallback whole, not split.
    final primary = _Without('Primary', {0x301});
    final fallback = _Without('Fallback', {}, extra: {0x301});
    final document = RecordingDocument();
    FlowLayout(
          template: const PageTemplate(
            Rect(0, 0, 300, 100),
            margins: EdgeInsets.all(10),
          ),
        )
        .layout([
          ParagraphBox(
            Paragraph([
              TextRun(
                'café ok',
                TextStyle(primary, 10),
                fallbackFonts: [fallback],
              ),
            ]),
          ),
        ])
        .render(document);
    final calls = document.pages.single.canvas.calls.join('\n');
    // (The e with its mark in the fallback's run, the rest in the text's.)
    final fallbackRuns = RegExp(r'glyphs "([^"]*)"[^\n]*Fallback')
        .allMatches(calls)
        .map((m) => m[1]!)
        .toList();
    expect(fallbackRuns.join().trim(), 'é');
  });

  test('a word too wide for its line splits between clusters', () {
    // A line 20 pt wide and a word of accented letters far wider: split
    // where it must be, each piece's marks with their bases.
    final word = List.filled(12, 'é').join();
    final document = RecordingDocument();
    FlowLayout(
          template: const PageTemplate(
            Rect(0, 0, 40, 400),
            margins: EdgeInsets.all(10),
          ),
        )
        .layout([
          ParagraphBox(Paragraph([TextRun(word, TextStyle(_serif, 10))])),
        ])
        .render(document);
    final pieces = [
      for (final page in document.pages) ...page.texts.map((t) => t.trim()),
    ].where((t) => t.isNotEmpty).toList();
    expect(pieces.length, greaterThan(1));
    for (final piece in pieces) {
      expect(piece.startsWith('́'), isFalse, reason: piece);
    }
    expect(pieces.join(), word);
  });

  test('flags are not split between lines', () {
    // Regional indicator pairs (a flag each), a word far wider than its
    // line: split between the flags, never inside one.
    final word = List.filled(10, '\u{1F1FA}\u{1F1F8}').join();
    final document = RecordingDocument();
    FlowLayout(
          template: const PageTemplate(
            Rect(0, 0, 40, 400),
            margins: EdgeInsets.all(10),
          ),
        )
        .layout([
          ParagraphBox(Paragraph([TextRun(word, TextStyle(_serif, 10))])),
        ])
        .render(document);
    final pieces = [
      for (final page in document.pages) ...page.texts.map((t) => t.trim()),
    ].where((t) => t.isNotEmpty).toList();
    expect(pieces.length, greaterThan(1));
    for (final piece in pieces) {
      expect(piece.runes.length.isEven, isTrue, reason: piece);
    }
  });
}
