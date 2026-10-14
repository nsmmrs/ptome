/// Ruby in the PDF (furigana, zhuyin): a base with its reading set above
/// it, as the W3C's "Requirements for Japanese Text Layout" (JLREQ 3.3)
/// has it: the reading half the base's size, centered on its base (a
/// group's on the whole, mono ruby's each on its character), resting on
/// the base's ascender; the part as wide as the wider of the two.
library;

import 'dart:math' as math;

import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:ptome/src/pdf/fonts.dart';

/// A ruby annotation in a line of text: [pairs] of base and reading,
/// laid out in the text's face and size when the line is ([at]).
final class InlineRuby implements Graphic {
  /// Ruby of [pairs] (one for group ruby, one a character for mono
  /// ruby), copied as [base].
  new(this.pairs, {required this.base});

  /// Each part of the base and its reading.
  final List<(String, String)> pairs;

  /// The base, the text a reader copies.
  final String base;

  final Map<(FontFace, double), RubyBox> _boxes = {};

  /// The ruby laid out in [face] at [size] points.
  RubyBox at(FontFace face, double size) =>
      _boxes[(face, size)] ??= RubyBox._(this, face, size);

  @override
  double get intrinsicWidth => 0;

  @override
  double get intrinsicHeight => 0;

  @override
  void paint(Canvas canvas, Rect rect) {}
}

/// Ruby laid out: its [width], how far it reaches above the baseline
/// ([ascent], its readings' tops) and below ([descent], the base's).
final class RubyBox {
  new _(this.ruby, this.face, this.size) {
    final readingSize = size / 2;
    var x = 0.0;
    for (final (base, reading) in ruby.pairs) {
      final baseWidth = face.widthOf(base, size);
      final readingWidth = face.widthOf(reading, readingSize);
      final width = math.max(baseWidth, readingWidth);
      _parts.add((
        base,
        x + (width - baseWidth) / 2,
        reading,
        x + (width - readingWidth) / 2,
      ));
      x += width;
    }
    width = x;
    _readingBaseline = face.ascenderAt(size) + face.descenderAt(readingSize);
    ascent = _readingBaseline + face.ascenderAt(readingSize);
    descent = face.descenderAt(size);
  }

  /// The ruby.
  final InlineRuby ruby;

  /// The face it is set in.
  final FontFace face;

  /// The base's size.
  final double size;

  /// Each part: its base and where it starts, its reading and where.
  final List<(String, double, String, double)> _parts = [];

  /// The width.
  late final double width;

  /// How far it reaches above the baseline.
  late final double ascent;

  /// How far it reaches below the baseline.
  late final double descent;

  /// How far above the baseline the readings' baseline is.
  late final double _readingBaseline;

  /// Draws the ruby with its baseline at [baseline], starting at [left],
  /// copied as its base.
  void paintAt(Canvas canvas, double left, double baseline, {Color? color}) {
    canvas
      ..save()
      ..beginMarkedContent('Span', actualText: ruby.base);
    if (color != null) canvas.setFillColor(color);
    final style = TextStyle(face.pdf, size);
    final readingStyle = TextStyle(face.pdf, size / 2);
    for (final (base, baseX, reading, readingX) in _parts) {
      canvas
        ..glyphs(style.shape(base), left + baseX, baseline, style, text: '')
        ..glyphs(
          readingStyle.shape(reading),
          left + readingX,
          baseline + _readingBaseline,
          readingStyle,
          text: '',
        );
    }
    canvas
      ..endMarkedContent()
      ..restore();
  }
}

/// Ruby drawn by the engine as an inline image: set in [face] at [size],
/// in [color].
final class EngineRuby implements Graphic {
  /// [ruby] in [face] at [size], in [color].
  const new(this.ruby, this.face, this.size, this.color);

  /// The ruby.
  final InlineRuby ruby;

  /// The face.
  final FontFace face;

  /// The base's size.
  final double size;

  /// The color, if not the text's default.
  final Color? color;

  @override
  double get intrinsicWidth => ruby.at(face, size).width;

  @override
  double get intrinsicHeight {
    final box = ruby.at(face, size);
    return box.ascent + box.descent;
  }

  @override
  void paint(Canvas canvas, Rect rect) {
    final box = ruby.at(face, size);
    box.paintAt(canvas, rect.left, rect.bottom + box.descent, color: color);
  }
}
