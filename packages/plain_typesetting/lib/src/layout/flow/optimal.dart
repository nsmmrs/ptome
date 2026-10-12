part of '../flow.dart';

// Pages chosen together rather than one at a time (Plass, "Optimal
// pagination techniques for automatic typesetting systems", 1981; after
// him, Mittelbach's globally optimized pagination): the content as a
// galley of pieces (paragraphs' lines, other blocks whole), the breaks
// between them that cost least over the whole document found by dynamic
// programming, and the content given those breaks as page breaks for the
// layout to follow.

/// How a layout chooses where its pages break.
enum Pagination {
  /// Each page as full as it goes, one after another.
  firstFit,

  /// The breaks that leave the least room unused over the whole document
  /// (the square of each page's, the last page's free): one nearly empty
  /// page after a block that wouldn't fit becomes a little room on
  /// several. Content the plan can't model (notes, floating boxes, page
  /// columns, tables or other blocks taller than a page, page templates
  /// of different sizes) is laid out first-fit.
  optimal,
}

/// A piece of the galley: [height] tall, the page may break after it
/// ([breakable]) or must ([forced]); [box] and [lines] say where (after
/// that many lines of a paragraph, or after the whole box when null).
final class _Piece {
  new(this.height, this.box, {this.lines, this.breakable = true});

  double height;
  final LayoutBox box;
  final int? lines;
  bool breakable;
  bool forced = false;
}

extension _Optimal on _Pass {
  /// [content] with the page breaks that cost least over the whole of it
  /// on pages whose text is [width] by [height]; null when the content
  /// has something the plan can't model.
  List<LayoutBox>? _optimallyPaged(
    List<LayoutBox> content,
    double width,
    double height,
  ) {
    final pieces = <_Piece>[];
    if (!_galley(content, width, pieces)) return null;
    if (pieces.isEmpty) return null;
    for (final piece in pieces) {
      if (piece.height > height + 1e-6) return null;
    }
    // The least cost of the pages up to each piece, and where the page
    // that ends there starts.
    final n = pieces.length;
    final best = List<double>.filled(n + 1, double.infinity)..[0] = 0;
    final start = List<int>.filled(n + 1, -1);
    for (var j = 1; j <= n; j++) {
      final end = pieces[j - 1];
      if (j < n && !end.breakable && !end.forced) continue;
      var used = 0.0;
      for (var i = j - 1; i >= 0; i--) {
        used += pieces[i].height;
        if (used > height + 1e-6) break;
        // (No page across a forced break.)
        if (i < j - 1 && pieces[i].forced) break;
        if (i > 0 && !pieces[i - 1].breakable && !pieces[i - 1].forced) {
          continue;
        }
        if (best[i].isInfinite) continue;
        final unused = (height - used) / height;
        final cost = j == n || end.forced ? 0.0 : unused * unused * 10000;
        if (best[i] + cost < best[j]) {
          best[j] = best[i] + cost;
          start[j] = i;
        }
      }
    }
    if (best[n].isInfinite) return null;
    // The breaks chosen (but those forced, which the content has).
    final breaks = <int>{};
    for (var j = n; j > 0; j = start[j]) {
      if (j < n && !pieces[j - 1].forced) breaks.add(j - 1);
    }
    final after = Set<LayoutBox>.identity();
    final splits = Map<LayoutBox, List<int>>.identity();
    for (final i in breaks) {
      final piece = pieces[i];
      switch (piece.lines) {
        case final lines?:
          (splits[piece.box] ??= []).add(lines);
        case null:
          after.add(piece.box);
      }
    }
    return _paged(content, width, after, splits);
  }

  /// Adds [boxes] to [pieces] as the plan reads them; false when one is
  /// something it can't model.
  bool _galley(List<LayoutBox> boxes, double width, List<_Piece> pieces) {
    for (final box in boxes) {
      final style = box.style;
      if (style.float != null || style.side != null) return false;
      switch (box) {
        case BreakBox(kind: BreakKind.page, template: null):
          if (pieces.isNotEmpty) pieces.last.forced = true;
          continue;
        case BreakBox():
          return false;
        case ColumnsBox():
          return false;
        case BlockBox(:final children) when _transparent(box):
          final from = pieces.length;
          if (!_galley(children, width - style.margin.horizontal, pieces)) {
            return false;
          }
          if (pieces.length > from) {
            pieces[from].height += style.margin.top;
            pieces.last.height += style.margin.bottom;
            if (style.keepWithNext) pieces.last.breakable = false;
          }
          continue;
        case ParagraphBox():
          final margin = style.margin;
          final lines = _linesOf(box, width - margin.horizontal);
          for (final (k, line) in lines.indexed) {
            final count = k + 1;
            pieces.add(
              _Piece(
                line.height +
                    (k == 0 ? margin.top : 0) +
                    (count == lines.length ? margin.bottom : 0),
                box,
                lines: count == lines.length ? null : count,
                breakable: count == lines.length
                    ? !style.keepWithNext
                    : count >= box.orphans &&
                          lines.length - count >= box.widows,
              ),
            );
          }
          continue;
        case CustomBox(:final content):
          final margin = style.margin;
          final inner = width - margin.horizontal;
          final whole = content.place(inner, double.infinity, atTop: true);
          final lines = whole?.lines ?? const [];
          if (whole != null && lines.length >= 4) {
            // (Lined text: a break between two lines, two kept on each
            // side, each line's share from midway between baselines.)
            var before = 0.0;
            for (var k = 0; k < lines.length; k++) {
              final count = k + 1;
              final last = count == lines.length;
              final below = last
                  ? whole.height
                  : (lines[k].baseline + lines[k + 1].baseline) / 2;
              pieces.add(
                _Piece(
                  below -
                      before +
                      (k == 0 ? margin.top : 0) +
                      (last ? margin.bottom : 0),
                  box,
                  lines: last ? null : count,
                  breakable: last
                      ? !style.keepWithNext
                      : count >= 2 && lines.length - count >= 2,
                ),
              );
              before = below;
            }
            continue;
          }
        case _:
      }
      // Anything else whole.
      pieces.add(
        _Piece(_measure(box, width), box, breakable: !style.keepWithNext),
      );
    }
    return true;
  }

  /// Whether [box] is a plain block the plan looks into.
  bool _transparent(BlockBox box) {
    final style = box.style;
    return style.padding == EdgeInsets.zero &&
        style.border == Border.none &&
        style.background == null &&
        style.decoration == null &&
        !style.keepTogether &&
        box.repeatedHead == 0 &&
        !box._containsMargins;
  }

  /// [boxes] with page breaks after the boxes in [after] and within the
  /// paragraphs in [splits] (after so many of their lines).
  List<LayoutBox> _paged(
    List<LayoutBox> boxes,
    double width,
    Set<LayoutBox> after,
    Map<LayoutBox, List<int>> splits,
  ) => [
    for (final box in boxes) ...[
      ..._split(box, width, after, splits),
      if (after.contains(box)) const BreakBox.page(),
    ],
  ];

  List<LayoutBox> _split(
    LayoutBox box,
    double width,
    Set<LayoutBox> after,
    Map<LayoutBox, List<int>> splits,
  ) {
    if (box is BlockBox && _transparent(box)) {
      return [
        BlockBox(
          _paged(
            box.children,
            width - box.style.margin.horizontal,
            after,
            splits,
          ),
          style: box.style,
        ),
      ];
    }
    final cuts = [...?splits[box]]..sort();
    if (cuts.isEmpty) return [box];
    switch (box) {
      case ParagraphBox():
        var from = 0;
        final pieces = <LayoutBox>[];
        for (final cut in cuts) {
          pieces
            ..add(ParagraphBox._slice(box, from, cut))
            ..add(const BreakBox.page());
          from = cut;
        }
        return [...pieces, ParagraphBox._rest(box, from)];
      case CustomBox(:final content, :final style):
        final inner = width - style.margin.horizontal;
        final pieces = <LayoutBox>[];
        CustomContent? rest = content;
        var done = 0;
        for (final cut in cuts) {
          final current = rest;
          if (current == null) break;
          final lines =
              current.place(inner, double.infinity, atTop: true)?.lines ??
              const [];
          final k = cut - done;
          if (k <= 0 || k >= lines.length) continue;
          final placed = current.place(
            inner,
            (lines[k - 1].baseline + lines[k].baseline) / 2,
            atTop: true,
          );
          if (placed == null || placed.rest == null) continue;
          final first = pieces.isEmpty;
          final piece = BoxStyle(
            margin: EdgeInsets(
              top: first ? style.margin.top : 0,
              left: style.margin.left,
              right: style.margin.right,
            ),
            anchor: first ? style.anchor : null,
            marks: first ? style.marks : const {},
            tag: style.tag,
          );
          pieces
            ..add(CustomBox(_Planned(placed, current), style: piece))
            ..add(const BreakBox.page());
          rest = placed.rest;
          done = cut;
        }
        if (rest == null || pieces.isEmpty) return [box];
        return [...pieces, CustomBox._rest(rest, style)];
      case _:
        return [box];
    }
  }
}

/// Content placed as a plan cut it: [placement] whole (what followed it
/// goes on after a page break).
final class _Planned implements CustomContent {
  const new(this.placement, this.source);

  final CustomPlacement placement;

  /// The content it was cut from (for its widths).
  final CustomContent source;

  @override
  CustomPlacement? place(
    double width,
    double available, {
    required bool atTop,
  }) => placement.height > available + 1e-6 && !atTop
      ? null
      : CustomPlacement(
          height: placement.height,
          paint: placement.paint,
          anchors: placement.anchors,
          lines: placement.lines,
        );

  @override
  double minHeight(double width) => placement.height;

  @override
  (double, double) intrinsicWidths() => source.intrinsicWidths();
}
