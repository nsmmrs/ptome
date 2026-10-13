part of '../flow.dart';

/// A paragraph the engine sets, as [CustomContent]: for content a caller
/// composes around a paragraph (a list item's marker beside it, a table
/// of contents entry's leader after it) and still has the layout place
/// and split. It breaks its lines once per width, keeps [orphans] and
/// [widows] as a [ParagraphBox] does, and what goes on after a break is
/// its line items after the lines set, broken again at the width it goes
/// on at.
final class ParagraphContent
    implements LinedContent, BaselineContent, ShapedContent {
  /// [paragraph], broken by [lineBreaker].
  new(
    this.paragraph, {
    this.lineBreaker = const KnuthPlassLineBreaker(),
    this.orphans = 2,
    this.widows = 2,
    this.slant = 0,
  }) : _items = null,
       _goesOn = false;

  new _rest(
    ParagraphContent source,
    this.paragraph,
    List<LineItem> this._items, {
    required this._goesOn,
  }) : lineBreaker = source.lineBreaker,
       orphans = source.orphans,
       widows = source.widows,
       slant = source.slant;

  /// Whether a rest's first line goes on with the line before it (a line
  /// that wrapped, which logical line numbers count once).
  final bool _goesOn;

  /// Whether [item] is a forced break (a hard line break).
  static bool _forced(LineItem item) => item is PenaltyItem && item.isForced;

  /// Whether each of the lines broken at [breaks] of [items] goes on with
  /// the line before it: one after a break that wasn't forced.
  List<bool> _continuations(List<int>? breaks, List<LineItem>? items, int n) =>
      [
        for (var i = 0; i < n; i++)
          if (i == 0)
            _goesOn
          else if (breaks == null || items == null)
            true
          else
            !_forced(items[breaks[i - 1]]),
      ];

  /// How far its lines lean as one block, the tangent of the angle: each
  /// line set right by this times its height above the piece's last
  /// baseline (with [TextStyle.skew] slanting the glyphs, a title slanted
  /// as a whole).
  final double slant;

  /// The paragraph.
  final Paragraph paragraph;

  /// What breaks its lines.
  final LineBreaker lineBreaker;

  @override
  final int orphans;

  @override
  final int widows;

  /// The line items of a rest, or null for the paragraph's own.
  final List<LineItem>? _items;

  final Map<
    double,
    ({List<Line> lines, List<int>? breaks, List<LineItem>? items})
  >
  _broken = {};

  ({List<Line> lines, List<int>? breaks, List<LineItem>? items}) _at(
    double width,
  ) => _broken[width] ??= switch (lineBreaker) {
    final ItemLineBreaker breaker => () {
      final items =
          _items ??
          paragraphItems(
            paragraph,
            maxWidth: paragraph.breakLongWords
                ? width - paragraph.firstLineIndent
                : null,
          );
      final (:lines, :breaks) = breaker.breakItemLines(
        paragraph,
        items,
        (_) => width,
      );
      return (lines: lines, breaks: breaks, items: items);
    }(),
    final breaker => (
      lines: breaker.breakLines(paragraph, (_) => width),
      breaks: null,
      items: null,
    ),
  };

  /// The lines at [width]: an empty paragraph's one empty line, as tall
  /// as its text's.
  List<Line> linesAt(double width) {
    final lines = _at(width).lines;
    if (lines.isNotEmpty || _items != null) return lines;
    final run = paragraph.content.whereType<TextRun>().firstOrNull;
    if (run == null) return lines;
    return _empty[width] ??= buildLines(
      paragraph,
      [const GlueItem.fill(), PenaltyItem(0, PenaltyItem.forced, run: run)],
      [1],
      (_) => width,
    );
  }

  final Map<double, List<Line>> _empty = {};

  @override
  int lineCount(double width) => linesAt(width).length;

  @override
  int linesThatFit(double width, double available) {
    final lines = linesAt(width);
    var top = 0.0;
    var count = 0;
    for (final line in lines) {
      // (A line fits when its text does: the space under it goes at a
      // break.)
      if (top + line.baseline - line.descent > available + 1e-6) break;
      top += line.height;
      count++;
    }
    return count;
  }

  @override
  CustomPlacement placeLines(double width, int count) {
    final lines = linesAt(width);
    final placed = lines.sublist(0, count);
    final (lines: _, :breaks, :items) = _at(width);
    return _placement(
      placed,
      count < lines.length ? _restAfter(width, count) : null,
      offsets: _slanted(placed),
      continues: _continuations(breaks, items, count),
    );
  }

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    final lines = linesAt(width);
    if (lines.isEmpty) return _placement(const [], null);
    var count = linesThatFit(width, available);
    if (count < lines.length && count > 0) {
      // (Orphans and widows, as the page breaker keeps them.)
      if (count < orphans) count = 0;
      if (lines.length - count < widows) {
        count = math.max(0, lines.length - widows);
        if (count < orphans) count = 0;
      }
    }
    if (count == 0) {
      if (!atTop) return null;
      count = 1;
    }
    return placeLines(width, count);
  }

  @override
  CustomPlacement? placeAround(
    double width,
    double available, {
    required bool atTop,
    required (double, double) Function(double top, double bottom) insets,
  }) {
    // (As a paragraph box runs around: the bands its lines would take at
    // their pitch across the width, each line broken in the room its band
    // leaves, the paragraph broken whole.)
    final breaker = lineBreaker;
    final plain = linesAt(width);
    if (breaker is! ItemLineBreaker || plain.isEmpty || slant != 0) {
      return place(width, available, atTop: atTop);
    }
    final pitch = (plain.length > 1 ? plain[1] : plain[0]).height;
    final gap = plain[0].baseline - plain[0].ascent;
    final count = available.isFinite
        ? (available / pitch).ceil() + 1
        : plain.length;
    final bands = [
      for (var i = 0; i < count; i++)
        insets(gap + i * pitch, gap + (i + 1) * pitch),
    ];
    final items = _at(width).items ?? paragraphItems(paragraph);
    final (:lines, :breaks) = breaker.breakItemLines(
      paragraph,
      items,
      (line) => line < count ? width - bands[line].$1 - bands[line].$2 : width,
      offsets: (line) => line < count ? bands[line].$1 : 0,
    );
    if (lines.isEmpty) return place(width, available, atTop: atTop);
    var fit = 0;
    var top = 0.0;
    for (final line in lines) {
      if (top + line.baseline - line.descent > available + 1e-6) break;
      top += line.height;
      fit++;
    }
    if (fit < lines.length && fit > 0) {
      if (fit < orphans) fit = 0;
      if (lines.length - fit < widows) {
        fit = math.max(0, lines.length - widows);
        if (fit < orphans) fit = 0;
      }
    }
    if (fit == 0) {
      if (!atTop) return null;
      fit = 1;
    }
    final rest = fit >= lines.length
        ? null
        : ParagraphContent._rest(
            this,
            paragraph.copyWith(
              firstLineIndent: 0,
              hangLines: math.max(0, paragraph.hangLines - fit),
            ),
            items.sublist(breaks[fit - 1] + 1),
            goesOn: !_forced(items[breaks[fit - 1]]),
          );
    return _placement(
      lines.sublist(0, fit),
      rest,
      continues: _continuations(breaks, items, fit),
    );
  }

  /// Each of [lines]' offsets by the [slant], or null without one.
  List<double>? _slanted(List<Line> lines) {
    if (slant == 0 || lines.isEmpty) return null;
    final baselines = <double>[];
    var top = 0.0;
    for (final line in lines) {
      baselines.add(top + line.baseline);
      top += line.height;
    }
    return [for (final b in baselines) slant * (baselines.last - b)];
  }

  /// What follows the first [count] lines at [width]: its items after
  /// them, to be broken again where it goes on.
  CustomContent _restAfter(double width, int count) {
    final (:lines, :breaks, :items) = _at(width);
    if (breaks == null || items == null) return _Lines(lines.sublist(count));
    return ParagraphContent._rest(
      this,
      paragraph.copyWith(
        firstLineIndent: 0,
        hangLines: math.max(0, paragraph.hangLines - count),
      ),
      items.sublist(breaks[count - 1] + 1),
      goesOn: !_forced(items[breaks[count - 1]]),
    );
  }

  /// The room it needs where it starts: its first [orphans] lines, or
  /// all of it when it's too short to split (no more lines than a break
  /// would leave on its two sides).
  @override
  double minHeight(double width) =>
      _leastHeight(linesAt(width), orphans, widows);

  @override
  double? firstBaseline(double width) => linesAt(width).firstOrNull?.baseline;

  @override
  (double, double) intrinsicWidths() {
    final items = _items ?? paragraphItems(paragraph);
    var widest = 0.0;
    var word = 0.0;
    for (final item in items) {
      switch (item) {
        case BoxItem(:final width):
          word += width;
        case _:
          widest = math.max(widest, word);
          word = 0;
      }
    }
    widest = math.max(widest, word);
    final natural = linesAt(1000000000)
        .fold<double>(0, (most, line) => math.max(most, line.width));
    return (widest + paragraph.firstLineIndent, natural);
  }
}

/// Lines already broken, placed as they are (the rest of a paragraph
/// whose breaker doesn't break items).
final class _Lines implements LinedContent, BaselineContent {
  const new(this.lines);

  final List<Line> lines;

  @override
  int get orphans => 1;

  @override
  int get widows => 1;

  @override
  int lineCount(double width) => lines.length;

  @override
  int linesThatFit(double width, double available) {
    var top = 0.0;
    var count = 0;
    for (final line in lines) {
      if (top + line.baseline - line.descent > available + 1e-6) break;
      top += line.height;
      count++;
    }
    return count;
  }

  @override
  CustomPlacement placeLines(double width, int count) => _placement(
    lines.sublist(0, count),
    count < lines.length ? _Lines(lines.sublist(count)) : null,
  );

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) {
    var count = linesThatFit(width, available);
    if (count == 0) {
      if (!atTop) return null;
      count = 1;
    }
    return placeLines(width, count);
  }

  @override
  double minHeight(double width) => lines.firstOrNull?.height ?? 0;

  @override
  double? firstBaseline(double width) => lines.firstOrNull?.baseline;

  @override
  (double, double) intrinsicWidths() {
    final widest = lines.fold<double>(0, (m, l) => math.max(m, l.width));
    return (widest, widest);
  }
}

/// The room [lines] need where they start: the first [orphans] of them,
/// or all of them when no more than a break would leave on its two sides.
double _leastHeight(List<Line> lines, int orphans, int widows) {
  if (lines.isEmpty) return 0;
  final least = math.max(1, orphans);
  final unsplit = math.max(least, least + widows - 1);
  final count = lines.length <= unsplit ? lines.length : least;
  // (Down to the last line's text: the space under it goes at a break.)
  final last = lines[count - 1];
  final below = math.max(0, last.height - last.baseline + last.descent);
  return lines.take(count).fold<double>(0, (sum, line) => sum + line.height) -
      below;
}

/// [lines] as a piece of custom content: painted from its top, its links
/// and anchors reported, [rest] after it; each line [offsets] in where
/// given.
CustomPlacement _placement(
  List<Line> lines,
  CustomContent? rest, {
  List<double>? offsets,
  List<bool>? continues,
}) {
  final anchors = <(String, double, double)>[];
  final pieceLines = <PieceLine>[];
  var y = 0.0;
  for (final (i, line) in lines.indexed) {
    final dx = offsets?[i] ?? 0;
    for (final fragment in line.fragmentsInReadingOrder) {
      if (fragment case TextFragment(:final run, :final style)
          when run.anchor != null) {
        anchors.add((
          run.anchor!,
          dx + fragment.x,
          y +
              line.baseline -
              (run.anchorOnBaseline
                  ? 0
                  : style.font.ascender * style.size / 1000),
        ));
      }
    }
    pieceLines.add(
      PieceLine(
        y + line.baseline,
        left: dx,
        right: dx + line.width,
        continues: continues?[i] ?? i > 0,
      ),
    );
    y += line.height;
  }
  // (A piece the region ends after: down to its last line's text, the
  // space under it going at the break.)
  if (rest != null && lines.isNotEmpty) {
    final last = lines.last;
    y -= math.max(0, last.height - last.baseline + last.descent);
  }
  return CustomPlacement(
    height: y,
    rest: rest,
    anchors: anchors,
    lines: pieceLines,
    paint: (page, x, top) {
      var at = top;
      for (final (i, line) in lines.indexed) {
        line.paint(page.canvas, x + (offsets?[i] ?? 0), at, link: page.link);
        at -= line.height;
      }
    },
  );
}
