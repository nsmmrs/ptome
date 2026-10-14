/// Warichu in the PDF: an inline cutting note set in two lines of text
/// half the line's size, within its line, as JLREQ 3.4 has it: no gap
/// between the two lines, together as tall as the line's characters; the
/// note broken where a line may break, its lines as near the same length
/// as that allows, the second never the longer; between parentheses as
/// large as the line's text, with no space between them and the text
/// around (their blank halves left out).
library;

import 'dart:math' as math;

import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart' show lineBreakOffsets;
import 'package:ptome/src/pdf/fonts.dart';

/// A warichu in a line of text: its [text] (a piece of a longer note,
/// [opens] and [closes] it), laid out in the text's face and size when the
/// line is ([at]).
final class InlineWarichu implements Graphic {
  /// The note's [text], the opening parenthesis before it where it
  /// [opens] the note, the closing one after where it [closes] it.
  new(this.text, {this.opens = true, this.closes = true});

  /// The note's text (of this piece).
  final String text;

  /// Whether the note starts here (its opening parenthesis).
  final bool opens;

  /// Whether the note ends here (its closing parenthesis).
  final bool closes;

  final Map<(FontFace, double, bool), WarichuBox> _boxes = {};

  /// The warichu laid out in [face] at [size] points, its characters
  /// upright in a [vertical] line.
  WarichuBox at(FontFace face, double size, {bool vertical = false}) =>
      _boxes[(face, size, vertical)] ??= WarichuBox._(
        this,
        face,
        size,
        vertical: vertical,
      );

  /// [note] in pieces whose two lines each fit [width] points at half of
  /// [size] in [face] (a note longer than its line goes on in the next).
  static List<InlineWarichu> pieces(
    String note,
    FontFace face,
    double size,
    double width,
  ) {
    final half = size / 2;
    final room = math.max(width - size, half * 2);
    final pieces = <String>[];
    var rest = note;
    while (face.widthOf(rest, half) > 2 * room) {
      // (Two lines' worth: up to the last break opportunity that fits.)
      final breaks = lineBreakOffsets(rest);
      var cut = 0;
      for (var i = 0; i < breaks.length; i++) {
        final at = breaks.offsetAt(i);
        if (face.widthOf(rest.substring(0, at), half) > 2 * room) break;
        cut = at;
      }
      if (cut == 0) break;
      pieces.add(rest.substring(0, cut));
      rest = rest.substring(cut);
    }
    pieces.add(rest);
    return [
      for (final (i, piece) in pieces.indexed)
        InlineWarichu(piece, opens: i == 0, closes: i == pieces.length - 1),
    ];
  }

  @override
  double get intrinsicWidth => 0;

  @override
  double get intrinsicHeight => 0;

  @override
  void paint(Canvas canvas, Rect rect) {}
}

/// A warichu laid out: its [width], how far it reaches above the baseline
/// ([ascent]) and below ([descent]).
final class WarichuBox {
  new _(this.warichu, this.face, this.size, {required this.vertical}) {
    final half = size / 2;
    final text = warichu.text;
    // The break that leaves the lines nearest the same length, the second
    // no longer than the first.
    final breaks = lineBreakOffsets(text);
    var first = text;
    var second = '';
    var best = double.infinity;
    for (var i = 0; i < breaks.length; i++) {
      final at = breaks.offsetAt(i);
      if (at >= text.length) continue;
      final a = _widthOf(text.substring(0, at), half);
      final b = _widthOf(text.substring(at), half);
      if (b > a) continue;
      if (a - b < best) {
        best = a - b;
        first = text.substring(0, at);
        second = text.substring(at);
      }
    }
    _lines = (first, second);
    final lineWidth = math.max(_widthOf(first, half), _widthOf(second, half));
    // (Each parenthesis's ink half: the blank half outside it left out.)
    final open = warichu.opens ? size / 2 : 0.0;
    final close = warichu.closes ? size / 2 : 0.0;
    _textX = open;
    width = open + lineWidth + close;
    ascent = face.ascenderAt(size);
    descent = face.descenderAt(size);
    // The two lines in the upper and the lower half of the line's em box.
    final middle = (ascent - descent) / 2;
    _firstBaseline = ascent - face.ascenderAt(half);
    _secondBaseline = middle - face.ascenderAt(half);
  }

  /// The warichu.
  final InlineWarichu warichu;

  /// The face it is set in.
  final FontFace face;

  /// The line's size.
  final double size;

  /// Whether it is set in a vertical line: its characters upright, by
  /// their vertical advances.
  final bool vertical;

  /// [text]'s length along the line at [size].
  double _widthOf(String text, double size) =>
      face.widthOf(text, size, vertical: vertical);

  late final (String, String) _lines;
  late final double _textX;
  late final double _firstBaseline;
  late final double _secondBaseline;

  /// The width.
  late final double width;

  /// How far it reaches above the baseline.
  late final double ascent;

  /// How far it reaches below the baseline.
  late final double descent;

  /// Draws the warichu with its baseline at [baseline], starting at
  /// [left], copied as its text (in its parentheses).
  void paintAt(Canvas canvas, double left, double baseline, {Color? color}) {
    final (first, second) = _lines;
    final copied =
        '${warichu.opens ? '（' : ''}${warichu.text}'
        '${warichu.closes ? '）' : ''}';
    canvas
      ..save()
      ..beginMarkedContent('Span', actualText: copied);
    if (color != null) canvas.setFillColor(color);
    final style = TextStyle(face.pdf, size, vertical: vertical);
    final note = TextStyle(face.pdf, size / 2, vertical: vertical);
    if (warichu.opens) {
      // (The full-width parenthesis's ink in its right half.)
      canvas.glyphs(
        style.shape('（'),
        left - size / 2,
        baseline,
        style,
        text: '',
      );
    }
    canvas
      ..glyphs(
        note.shape(first),
        left + _textX,
        baseline + _firstBaseline,
        note,
        text: '',
      )
      ..glyphs(
        note.shape(second),
        left + _textX,
        baseline + _secondBaseline,
        note,
        text: '',
      );
    if (warichu.closes) {
      canvas.glyphs(
        style.shape('）'),
        left + width - size / 2,
        baseline,
        style,
        text: '',
      );
    }
    canvas
      ..endMarkedContent()
      ..restore();
  }
}

/// Warichu drawn by the engine as an inline image, laid out ([box]), in
/// [color].
final class EngineWarichu implements Graphic {
  /// [box] in [color].
  const new(this.box, this.color);

  /// The warichu laid out.
  final WarichuBox box;

  /// The color, if not the text's default.
  final Color? color;

  @override
  double get intrinsicWidth => box.width;

  @override
  double get intrinsicHeight => box.ascent + box.descent;

  @override
  void paint(Canvas canvas, Rect rect) {
    box.paintAt(canvas, rect.left, rect.bottom + box.descent, color: color);
  }
}
