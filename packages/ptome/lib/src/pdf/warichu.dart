/// Warichu in the PDF: an inline cutting note set in two lines of text
/// half the line's size, within its line, as JLREQ 3.4 has it: no gap
/// between the two lines, together as tall as the line's characters; the
/// note broken where a line may break, its lines as near the same length
/// as that allows, the second never the longer; between parentheses as
/// large as the line's text, with no space between them and the text
/// around (their blank halves left out). A note longer than the rest of
/// its line fills it and goes on at the next line's start, each part
/// balanced in its own two lines (3.4.2, Fig. 148).
///
/// The note is cut into cells of two of its segments (the text between
/// two places a line may break), each as long along the line as the
/// longer of the two, the parentheses on the first and the last: the
/// cells of a part, side by side on a line, take the room of that part's
/// two balanced lines, and the line may break between any two.
library;

import 'dart:math' as math;

import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:plain_unicode/plain_unicode.dart' show lineBreakOffsets;
import 'package:ptome/src/pdf/fonts.dart';

/// A cell of a warichu note: the note's text from [start] to [end] (two
/// segments, meeting at [split]), the opening parenthesis before it where
/// it [opens] the note, the closing one after where it [closes] it; laid
/// out in the text's face and size when the line is ([at]).
final class InlineWarichu implements Graphic {
  /// The cell of the note [id], [note], from [start] to [end].
  new(
    this.id,
    this.note,
    this.start,
    this.end, {
    this.split,
    this.opens = true,
    this.closes = true,
  });

  /// The note the cell is of: its cells share it.
  final Object id;

  /// The whole note's text.
  final String note;

  /// Where the cell starts in [note], in code units.
  final int start;

  /// Where it ends.
  final int end;

  /// Where its two segments meet (null: one segment).
  final int? split;

  /// Whether the note starts here (its opening parenthesis).
  final bool opens;

  /// Whether the note ends here (its closing parenthesis).
  final bool closes;

  /// The cell's text.
  String get text => note.substring(start, end);

  final Map<(FontFace, double, bool), WarichuCell> _cells = {};

  /// The cell laid out in [face] at [size] points, its characters upright
  /// in a [vertical] line.
  WarichuCell at(FontFace face, double size, {bool vertical = false}) =>
      _cells[(face, size, vertical)] ??= WarichuCell._(
        this,
        face,
        size,
        vertical: vertical,
      );

  /// [note] in cells of two segments each (the text between two places a
  /// line may break), the first opening it and the last closing it.
  static List<InlineWarichu> cells(String note) {
    final id = Object();
    final breaks = lineBreakOffsets(note);
    final ends = [
      for (var i = 0; i < breaks.length; i++)
        if (breaks.offsetAt(i) case final at when at > 0 && at <= note.length)
          at,
    ];
    if (ends.isEmpty || ends.last != note.length) ends.add(note.length);
    final cells = <InlineWarichu>[];
    var start = 0;
    for (var i = 0; i < ends.length; i += 2) {
      final paired = i + 1 < ends.length;
      final end = paired ? ends[i + 1] : ends[i];
      cells.add(
        InlineWarichu(
          id,
          note,
          start,
          end,
          split: paired ? ends[i] : null,
          opens: start == 0,
          closes: end == note.length,
        ),
      );
      start = end;
    }
    return cells;
  }

  @override
  double get intrinsicWidth => 0;

  @override
  double get intrinsicHeight => 0;

  @override
  void paint(Canvas canvas, Rect rect) {}
}

/// A warichu cell's measure: its [width] along the line (the longer of
/// its segments at half the size, and a parenthesis's half where it opens
/// or closes the note), how far it reaches above the baseline ([ascent])
/// and below ([descent]).
final class WarichuCell {
  new _(this.warichu, this.face, this.size, {required this.vertical}) {
    final half = size / 2;
    final note = warichu.note;
    final split = warichu.split;
    final segments = split == null
        ? [note.substring(warichu.start, warichu.end)]
        : [
            note.substring(warichu.start, split),
            note.substring(split, warichu.end),
          ];
    final longest = segments
        .map((s) => face.widthOf(s, half, vertical: vertical))
        .reduce(math.max);
    width =
        longest +
        (warichu.opens ? size / 2 : 0) +
        (warichu.closes ? size / 2 : 0);
    ascent = face.ascenderAt(size);
    descent = face.descenderAt(size);
  }

  /// The cell.
  final InlineWarichu warichu;

  /// The face it is set in.
  final FontFace face;

  /// The line's size.
  final double size;

  /// Whether it is set in a vertical line.
  final bool vertical;

  /// Its length along the line.
  late final double width;

  /// How far it reaches above the baseline.
  late final double ascent;

  /// How far it reaches below the baseline.
  late final double descent;
}

/// The part of a warichu note on a line, from the first of its cells to
/// the last: their text in two lines as near the same length as its
/// places to break allow (the second never the longer), each spaced out
/// to the cells' room, between the parentheses where the part opens or
/// closes the note.
final class WarichuPart {
  /// The part made of [cells] in [face] at [size].
  new(List<InlineWarichu> cells, this.face, this.size, {required this.vertical})
    : text = cells.first.note.substring(cells.first.start, cells.last.end),
      opens = cells.first.opens,
      closes = cells.last.closes {
    final half = size / 2;
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
    final ascent = face.ascenderAt(size);
    final descent = face.descenderAt(size);
    final middle = (ascent - descent) / 2;
    _firstBaseline = ascent - face.ascenderAt(half);
    _secondBaseline = middle - face.ascenderAt(half);
  }

  /// The part's text.
  final String text;

  /// Whether the note starts here.
  final bool opens;

  /// Whether the note ends here.
  final bool closes;

  /// The face it is set in.
  final FontFace face;

  /// The line's size.
  final double size;

  /// Whether it is set in a vertical line: its characters upright, by
  /// their vertical advances.
  final bool vertical;

  double _widthOf(String text, double size) =>
      face.widthOf(text, size, vertical: vertical);

  late final (String, String) _lines;
  late final double _firstBaseline;
  late final double _secondBaseline;

  /// Draws the part with its baseline at [baseline] from [left] to
  /// [right] (its cells' room), copied as its text (in its parentheses).
  void paintAt(
    Canvas canvas,
    double left,
    double right,
    double baseline, {
    Color? color,
  }) {
    final (first, second) = _lines;
    final copied = '${opens ? '（' : ''}$text${closes ? '）' : ''}';
    canvas
      ..save()
      ..beginMarkedContent('Span', actualText: copied);
    if (color != null) canvas.setFillColor(color);
    final style = TextStyle(face.pdf, size, vertical: vertical);
    final note = TextStyle(face.pdf, size / 2, vertical: vertical);
    if (opens) {
      // (The full-width parenthesis's ink in its right half.)
      canvas.glyphs(
        style.shape('（'),
        left - size / 2,
        baseline,
        style,
        text: '',
      );
    }
    final textX = left + (opens ? size / 2 : 0);
    // (Each line set to the part's room, its characters spaced evenly: the
    // two lines the same length, filling the cells' room, JLREQ 3.4.)
    final room = right - (closes ? size / 2 : 0) - textX;
    for (final (line, y) in [
      (first, _firstBaseline),
      (second, _secondBaseline),
    ]) {
      final glyphs = note.shape(line);
      final extra = room - note.widthOf(glyphs);
      final spaced = glyphs.length > 1 && extra > 0
          ? note.copyWith(characterSpacing: extra / (glyphs.length - 1))
          : note;
      canvas.glyphs(glyphs, textX, baseline + y, spaced, text: '');
    }
    if (closes) {
      canvas.glyphs(
        style.shape('）'),
        right - size / 2,
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

/// A warichu cell drawn by the engine as an inline image ([cell]), in
/// [color]: the cells of a part beside one another on a line drawn as one
/// ([paintPieces]).
final class EngineWarichu implements SplitGraphic {
  /// [cell] in [color].
  const new(this.cell, this.color);

  /// The cell laid out.
  final WarichuCell cell;

  /// The color, if not the text's default.
  final Color? color;

  @override
  Object get group => cell.warichu.id;

  @override
  double get intrinsicWidth => cell.width;

  @override
  double get intrinsicHeight => cell.ascent + cell.descent;

  @override
  void paint(Canvas canvas, Rect rect) => paintPieces(canvas, [(this, rect)]);

  @override
  void paintPieces(Canvas canvas, List<(SplitGraphic, Rect)> pieces) {
    final first = pieces.first.$2;
    final last = pieces.last.$2;
    WarichuPart(
      [
        for (final (piece, _) in pieces)
          if (piece case EngineWarichu(:final cell)) cell.warichu,
      ],
      cell.face,
      cell.size,
      vertical: cell.vertical,
    ).paintAt(
      canvas,
      first.left,
      last.left + last.width,
      first.bottom + cell.descent,
      color: color,
    );
  }
}
