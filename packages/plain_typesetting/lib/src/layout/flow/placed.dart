part of '../flow.dart';

// What a pass placed, and how it paints.

/// What placing a box gave: the placed part, its height, and the rest
/// (null when all of it was placed).
final class _Fit {
  const new(
    this.placed,
    this.height,
    this.rest, {
    this.hit,
    this.floated = const [],
    this.pinned = const [],
    this.carried = const [],
  });

  /// Nothing placed: all of [box] goes to the next region.
  const new moved(LayoutBox box)
    : placed = null,
      height = 0,
      rest = box,
      hit = null,
      floated = const [],
      pinned = const [],
      carried = const [];

  final _Placed? placed;
  final double height;
  final LayoutBox? rest;

  /// The forced break that ended the placing.
  final BreakBox? hit;

  /// Floating boxes that didn't fit, for the top of the next region.
  final List<LayoutBox> floated;

  /// Floating boxes that fit, for the top or bottom of the region: each
  /// with its top (from the placed part's top) and height.
  final List<(LayoutBox, double, double)> pinned;

  /// What is left of blocks floating to a side ([BoxStyle.side]), for the
  /// top of the next region (each floating to its side).
  final List<LayoutBox> carried;
}

/// Where a block floating to a side is in its region: across from [left]
/// to [right] (from the region's left), down from [top] to [bottom] (from
/// its top; infinite when it goes on in the next region), the blocks
/// beside it [gap] from it.
final class _Exclusion {
  const new(
    this.side,
    this.left,
    this.right, {
    required this.gap,
    required this.top,
    required this.bottom,
    this.shape,
  });

  final FloatSide side;
  final double left;
  final double right;
  final double gap;
  final double top;
  final double bottom;

  /// Its outline (from its top left), when it isn't its box.
  final FloatShape? shape;

  /// What it covers between [from] and [to], down the region: from left
  /// to right, or null for nothing.
  (double, double)? covered(double from, double to) {
    if (to <= top + 1e-6 || from >= bottom - 1e-6) return null;
    final outline = shape;
    if (outline == null) return (left, right);
    double? low;
    double? high;
    final first = math.max(0, ((from - top) / outline.bandHeight).floor());
    final last = ((to - top) / outline.bandHeight).ceil() - 1;
    for (var i = first; i <= last; i++) {
      final (a, b) = i < outline.bands.length
          ? outline.bands[i] ?? (double.nan, double.nan)
          : (0.0, right - left);
      if (a.isNaN) continue;
      low = math.min(low ?? a, a);
      high = math.max(high ?? b, b);
    }
    return low == null ? null : (left + low, left + high!);
  }
}

final class _Page {
  new(this.template);

  final PageTemplate template;
  final List<(Rect, _Placed?)> placed = [];

  /// The side notes set on the page (see [FlowLayout.sideNotes]).
  final List<(Rect, _Placed?)> side = [];

  /// The top of the highest notes set at the bottom of a region of the
  /// page, which side notes stay above.
  double? notesTop;

  /// The marks set on the page, in order.
  final List<(String, String)> marks = [];
}

/// A placed piece of a box, positioned relative to the top left of the
/// space it was placed in.
sealed class _Placed {
  const new();

  double get height;

  /// Reports the anchors and marks of the piece at ([x], [top]).
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  );

  /// Paints the piece at ([x], [top]).
  void paint(_Painter painter, double x, double top);
}

final class _Painter {
  new(this.canvas, this.page);

  final Canvas canvas;
  final LayoutPage page;

  /// How many of the blocks being painted number their lines.
  int numbering = 0;

  /// The numbered lines painted, in order.
  final List<TypesetLine> lines = [];
}

/// What a box with [BoxStyle.unnumbered] placed: painted with the lines
/// it holds left out of the numbering.
final class _PlacedUnnumbered extends _Placed {
  const new(this.placed);

  final _Placed placed;

  @override
  double get height => placed.height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) => placed.visit(x, top, anchor, mark, tag);

  @override
  void paint(_Painter painter, double x, double top) {
    final numbering = painter.numbering;
    painter.numbering = 0;
    placed.paint(painter, x, top);
    painter.numbering = numbering;
  }
}

/// [placed] painted as [element]'s content (on a [StructureCanvas]).
final class _PlacedTagged extends _Placed {
  const new(this.element, this.placed);

  final StructureElement element;
  final _Placed placed;

  @override
  double get height => placed.height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) => placed.visit(x, top, anchor, mark, tag);

  @override
  void paint(_Painter painter, double x, double top) {
    final canvas = painter.canvas;
    if (canvas is! StructureCanvas) return placed.paint(painter, x, top);
    canvas.beginStructure(element);
    placed.paint(painter, x, top);
    canvas.endStructure();
  }
}

final class _PlacedSpace extends _Placed {
  const new(this.height);

  @override
  final double height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {}

  @override
  void paint(_Painter painter, double x, double top) {}
}

final class _PlacedBlock extends _Placed {
  const new(
    this.style,
    this.width,
    this.height,
    this.children, {
    required this.top,
    required this.openTop,
    required this.openBottom,
    required this.marks,
    required this.anchor,
    this.marginBottom,
  });

  final BoxStyle style;
  final double width;
  @override
  final double height;

  /// The margin below taken (of a last piece), when less than the
  /// style's.
  final double? marginBottom;

  /// The children and their offsets below the content top.
  final List<(double, _Placed)> children;

  /// The top margin taken.
  final double top;

  final bool openTop;
  final bool openBottom;
  final Map<String, String> marks;
  final String? anchor;

  /// Whether the piece has the block's top and bottom edges (padding and
  /// border): the first and last piece's, or every piece's with
  /// [BoxStyle.cloneEdges].
  bool get _topEdge => !openTop || style.cloneEdges;
  bool get _bottomEdge => !openBottom || style.cloneEdges;

  double get _contentTop =>
      top + (_topEdge ? style.border.widths.top + style.padding.top : 0);

  double get _contentLeft =>
      style.margin.left + style.border.widths.left + style.padding.left;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) {
      anchor(name, x + style.margin.left, top - this.top);
    }
    if (style.tag case final name?) tag(name);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    for (final (offset, child) in children) {
      child.visit(
        x + _contentLeft,
        top - _contentTop - offset,
        anchor,
        mark,
        tag,
      );
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final canvas = painter.canvas;
    final border = style.border;
    final left = x + style.margin.left;
    final boxWidth = width - style.margin.horizontal;
    final boxTop = top - this.top;
    final bottomMargin = openBottom ? 0 : marginBottom ?? style.margin.bottom;
    final boxHeight = height - this.top - bottomMargin;
    final rect = Rect(left, boxTop - boxHeight, boxWidth, boxHeight);
    // (A block's background and border no part of its content.)
    final structure = switch (canvas) {
      final StructureCanvas canvas
          when style.background != null ||
              style.border.widths != EdgeInsets.zero =>
        canvas,
      _ => null,
    };
    structure?.beginArtifact();
    final uniform =
        border.widths.top == border.widths.left &&
        border.widths.left == border.widths.right &&
        border.widths.right == border.widths.bottom &&
        _topEdge &&
        _bottomEdge;
    if (style.background case final background?) {
      canvas
        ..save()
        ..setFillColor(background);
      if (border.radius > 0 && uniform) {
        canvas.roundedRect(rect, border.radius);
      } else {
        canvas.rect(rect);
      }
      canvas
        ..fill()
        ..restore();
    }
    final widths = border.widths;
    if (widths != EdgeInsets.zero) {
      canvas
        ..save()
        ..setStrokeColor(border.color);
      if (uniform && widths.top > 0) {
        final w = widths.top;
        final inset = Rect(
          rect.left + w / 2,
          rect.bottom + w / 2,
          rect.width - w,
          rect.height - w,
        );
        canvas.setLineWidth(w);
        if (border.radius > 0) {
          canvas.roundedRect(inset, math.max(0, border.radius - w / 2));
        } else {
          canvas.rect(inset);
        }
        canvas.stroke();
      } else {
        void side(double w, double x1, double y1, double x2, double y2) {
          if (w <= 0) return;
          canvas
            ..setLineWidth(w)
            ..moveTo(x1, y1)
            ..lineTo(x2, y2)
            ..stroke();
        }

        final Rect(left: l, bottom: b, right: r, top: t) = rect;
        if (_topEdge) {
          side(widths.top, l, t - widths.top / 2, r, t - widths.top / 2);
        }
        if (_bottomEdge) {
          side(
            widths.bottom,
            l,
            b + widths.bottom / 2,
            r,
            b + widths.bottom / 2,
          );
        }
        side(widths.left, l + widths.left / 2, b, l + widths.left / 2, t);
        side(widths.right, r - widths.right / 2, b, r - widths.right / 2, t);
      }
      canvas.restore();
    }
    structure?.endArtifact();
    style.decoration?.call(
      painter.page,
      rect,
      first: _topEdge,
      last: _bottomEdge,
    );
    if (style.numberLines) painter.numbering++;
    for (final (offset, child) in children) {
      child.paint(painter, x + _contentLeft, top - _contentTop - offset);
    }
    if (style.numberLines) painter.numbering--;
  }
}

final class _PlacedLines extends _Placed {
  const new(
    this.lines,
    this.left,
    this.top,
    this.height,
    this.anchor,
    this.marks,
    this.tag, {
    required this.first,
  });

  final Map<String, String> marks;

  /// The paragraph's tag ([BoxStyle.tag]).
  final String? tag;

  /// Whether the lines start the paragraph.
  final bool first;

  final List<Line> lines;
  final double left;
  final double top;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
    if (this.tag case final name?) tag(name);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    var y = top - this.top;
    for (final line in lines) {
      for (final fragment in line.fragmentsInReadingOrder) {
        if (fragment case TextFragment(:final run, :final style)
            when run.anchor != null) {
          anchor(
            run.anchor!,
            x + left + fragment.x,
            y -
                line.baseline +
                (run.anchorOnBaseline
                    ? 0
                    : style.font.ascender * style.size / 1000),
          );
        }
      }
      y -= line.height;
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    var y = top - this.top;
    for (final (i, line) in lines.indexed) {
      line.paint(painter.canvas, x + left, y, link: painter.page.link);
      if (painter.numbering > 0) {
        painter.lines.add(
          TypesetLine(
            y - line.baseline,
            left: x + left,
            right: x + left + line.width,
            continues: i > 0 || !first,
          ),
        );
      }
      y -= line.height;
    }
  }
}

final class _PlacedImage extends _Placed {
  const new(
    this.image,
    this.left,
    this.top,
    this.width,
    this.imageHeight,
    this.height,
    this.anchor, {
    this.writingMode = WritingMode.horizontal,
  });

  /// The page's writing mode: on a vertical page the image is laid out
  /// turned ([width] its height) and painted turned back upright.
  final WritingMode writingMode;

  final Graphic image;
  final double left;
  final double top;
  final double width;
  final double imageHeight;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final rect = Rect(
      x + left,
      top - this.top - imageHeight,
      width,
      imageHeight,
    );
    // (Vertical: in the image's own upright space, its width across the
    // page the frame's height, turned (and, where the frame is mirrored,
    // mirrored) into the frame.)
    final matrix = switch (writingMode) {
      WritingMode.horizontal => null,
      WritingMode.verticalRightToLeft => Matrix(
        0,
        1,
        -1,
        0,
        rect.left + rect.width,
        rect.bottom,
      ),
      WritingMode.verticalLeftToRight => Matrix(
        0,
        -1,
        -1,
        0,
        rect.left + rect.width,
        rect.bottom + rect.height,
      ),
    };
    if (matrix == null) return image.paint(painter.canvas, rect);
    painter.canvas.saved(() {
      painter.canvas.transform(matrix);
      image.paint(painter.canvas, Rect(0, 0, rect.height, rect.width));
    });
  }
}

/// A box laid out across the page, placed upright in a vertical page's
/// turned frame: [length] along the line (its height down the page),
/// [across] in the flow (its width across the page).
final class _PlacedUpright extends _Placed {
  const new(
    this.placed,
    this.top,
    this.length,
    this.across,
    this.height,
    this.writingMode,
  );

  final _Placed placed;
  final double top;
  final double length;
  final double across;
  @override
  final double height;
  final WritingMode writingMode;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    // (Its anchors where it starts.)
    placed.visit(
      0,
      length,
      (name, _, _) => anchor(name, x, top - this.top),
      mark,
      tag,
    );
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final rect = Rect(x, top - this.top - across, length, across);
    // (In its own upright space, its width across the page, turned (and,
    // where the frame is mirrored, mirrored) into the frame, as an image.)
    final matrix = switch (writingMode) {
      WritingMode.verticalLeftToRight => Matrix(
        0,
        -1,
        -1,
        0,
        rect.left + rect.width,
        rect.bottom + rect.height,
      ),
      _ => Matrix(0, 1, -1, 0, rect.left + rect.width, rect.bottom),
    };
    painter.canvas.saved(() {
      painter.canvas.transform(matrix);
      placed.paint(painter, 0, length);
    });
  }
}

/// A box placed mirrored: [placed] at [left], [width] wide, [top] down,
/// turned over about its vertical middle.
final class _PlacedMirrored extends _Placed {
  const new(this.placed, this.top, this.left, this.width, this.height);

  final _Placed placed;
  final double top;
  final double left;
  final double width;
  @override
  final double height;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    placed.visit(x + left, top - this.top, anchor, mark, tag);
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final from = x + left;
    // (x' = 2·from + width − x: its left edge where its right was.)
    painter.canvas.saved(() {
      painter.canvas.transform(Matrix(-1, 0, 0, 1, 2 * from + width, 0));
      placed.paint(painter, from, top - this.top);
    });
  }
}

/// A box laid out in a turned frame, placed on a horizontal page in
/// vertical lines: [length] down the page (its columns' length), [across]
/// the page (its columns' extent).
final class _PlacedTurned extends _Placed {
  const new(
    this.placed,
    this.top,
    this.length,
    this.across,
    this.height,
    this.writingMode,
  );

  final _Placed placed;
  final double top;
  final double length;
  final double across;
  @override
  final double height;
  final WritingMode writingMode;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    placed.visit(
      0,
      across,
      (name, _, _) => anchor(name, x, top - this.top),
      mark,
      tag,
    );
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final bottom = top - this.top - length;
    // (Its frame turned onto the page as a vertical page's: its first line
    // at the right (vertical-rl) or the left (vertical-lr), running down.)
    final matrix = switch (writingMode) {
      WritingMode.verticalLeftToRight => Matrix(
        0,
        -1,
        -1,
        0,
        x + across,
        bottom + length,
      ),
      _ => Matrix(0, -1, 1, 0, x, bottom + length),
    };
    painter.canvas.saved(() {
      painter.canvas.transform(matrix);
      placed.paint(painter, 0, across);
    });
  }
}

final class _PlacedDrawing extends _Placed {
  const new(
    this.draw,
    this.left,
    this.top,
    this.width,
    this.drawingHeight,
    this.height,
    this.anchor,
  );

  final void Function(Canvas canvas, Rect rect) draw;
  final double left;
  final double top;
  final double width;
  final double drawingHeight;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
  }

  @override
  void paint(_Painter painter, double x, double top) {
    painter.canvas.saved(
      () => draw(
        painter.canvas,
        Rect(x + left, top - this.top - drawingHeight, width, drawingHeight),
      ),
    );
  }
}

final class _PlacedCustom extends _Placed {
  const new(
    this.placement,
    this.left,
    this.top,
    this.height,
    this.anchor,
    this.marks, {
    required this.width,
    this.decoration,
    this.first = true,
    this.last = true,
    this.tag,
  });

  final double width;
  final BoxDecoration? decoration;

  /// The box's tag ([BoxStyle.tag]).
  final String? tag;
  final bool first;
  final bool last;

  final CustomPlacement placement;
  final double left;
  final double top;
  @override
  final double height;
  final String? anchor;
  final Map<String, String> marks;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.tag case final name?) tag(name);
    if (this.anchor case final name?) anchor(name, x + left, top - this.top);
    marks.entries.map((e) => (e.key, e.value)).forEach(mark);
    for (final (name, dx, dy) in placement.anchors) {
      anchor(name, x + left + dx, top - this.top - dy);
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    decoration?.call(
      painter.page,
      Rect(
        x + left,
        top - this.top - placement.height,
        width,
        placement.height,
      ),
      first: first,
      last: last,
    );
    placement.paint(painter.page, x + left, top - this.top);
    if (painter.numbering > 0) {
      for (final line in placement.lines) {
        painter.lines.add(
          TypesetLine(
            top - this.top - line.baseline,
            left: x + left + line.left,
            right: x + left + line.right,
            continues: line.continues,
          ),
        );
      }
    }
  }
}

final class _PlacedColumns extends _Placed {
  const new(this.columns, this.top, this.height, this.gap, this.rule);

  final List<(double, _Placed)> columns;
  final double top;
  @override
  final double height;
  final double gap;
  final ColumnRule? rule;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    for (final (left, column) in columns) {
      column.visit(x + left, top - this.top, anchor, mark, tag);
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    for (final (left, column) in columns) {
      column.paint(painter, x + left, top - this.top);
    }
    if (rule case final rule? when rule.width > 0) {
      final canvas = painter.canvas
        ..save()
        ..setStrokeColor(rule.color)
        ..setLineWidth(rule.width);
      for (var i = 1; i < columns.length; i++) {
        final (left, column) = columns[i];
        final down = math.max(column.height, columns[i - 1].$2.height);
        final at = x + left - gap / 2;
        canvas
          ..moveTo(at, top - this.top)
          ..lineTo(at, top - this.top - down)
          ..stroke();
      }
      canvas.restore();
    }
  }
}

final class _PlacedCell {
  const new(
    this.cell,
    this.x,
    this.y,
    this.width,
    this.height,
    this.content,
    this.contentHeight, {
    required this.openBottom,
    required this.row,
    this.stripe,
    this.header = false,
    this.repeated = false,
  });

  final TableCell cell;

  /// The row the cell starts in.
  final Object row;

  /// Whether the cell is in a header row.
  final bool header;

  /// Whether the cell is a header row's repeated on a table's later piece.
  final bool repeated;

  /// The background of the cell's row, for a cell without its own.
  final Color? stripe;

  /// The left edge, from the table's region's left.
  final double x;

  /// The top edge, below the table's top.
  final double y;
  final double width;
  final double height;
  final _Placed? content;
  final double contentHeight;
  final bool openBottom;

  double get _contentTop {
    final padding = cell.padding;
    final room = height - padding.vertical;
    if (cell.verticalOffset case final offset?) {
      return y + padding.top + offset(room, contentHeight);
    }
    return y +
        padding.top +
        switch (cell.verticalAlign) {
          VerticalAlign.top => 0,
          VerticalAlign.middle => (room - contentHeight) / 2,
          VerticalAlign.bottom => room - contentHeight,
        };
  }
}

final class _PlacedTable extends _Placed {
  const new(
    this.cells,
    this.height,
    this.anchor,
    this.tag,
    this.borders, {
    this.tagged = false,
  });

  final List<_PlacedCell> cells;

  /// Whether the table's rows and cells are elements of the document's
  /// structure (the table is one).
  final bool tagged;

  /// The `TR` of each row, the `TH` or `TD` of each cell, the same
  /// elements for each piece of a table.
  static final Expando<StructureElement> _rows = Expando();
  static final Expando<StructureElement> _cells = Expando();

  /// The `TR` each cell began in.
  static final Expando<StructureElement> _cellRows = Expando();

  /// When the cells' borders are painted.
  final TableBorders borders;

  /// The table's tag ([BoxStyle.tag]).
  final String? tag;
  @override
  final double height;
  final String? anchor;

  @override
  void visit(
    double x,
    double top,
    void Function(String anchor, double x, double y) anchor,
    void Function((String, String) mark) mark,
    void Function(String tag) tag,
  ) {
    if (this.anchor case final name?) anchor(name, x, top);
    if (this.tag case final name?) tag(name);
    for (final cell in cells) {
      cell.content?.visit(
        x + cell.x + cell.cell.padding.left,
        top - cell._contentTop,
        anchor,
        mark,
        tag,
      );
    }
  }

  @override
  void paint(_Painter painter, double x, double top) {
    final canvas = painter.canvas;
    // (The cells' backgrounds and borders no part of the table's content.)
    final structure = switch (canvas) {
      final StructureCanvas canvas when tagged => canvas,
      _ => null,
    };
    structure?.beginArtifact();
    for (final placed in cells) {
      if (placed.cell.background ?? placed.stripe case final background?) {
        canvas
          ..save()
          ..setFillColor(background)
          ..rect(
            Rect(
              x + placed.x,
              top - placed.y - placed.height,
              placed.width,
              placed.height,
            ),
          )
          ..fill()
          ..restore();
      }
    }
    structure?.endArtifact();
    void content(_PlacedCell placed) {
      void paint() => placed.content?.paint(
        painter,
        x + placed.x + placed.cell.padding.left,
        top - placed._contentTop,
      );
      if (!tagged || canvas is! StructureCanvas) return paint();
      // (A repeated header no part of the content; the others a row's
      // cells, header cells heading their columns.)
      if (placed.repeated) {
        canvas.beginArtifact();
        paint();
        canvas.endArtifact();
        return;
      }
      final cell = placed.cell._source ?? placed.cell;
      // (A cell's later piece, carried past a break, goes on in the row
      // its cell began in: a row of its own would be left empty.)
      final row = _cellRows[cell] ??= _rows[placed.row] ??= StructureElement(
        'TR',
      );
      canvas
        ..beginStructure(row)
        ..beginStructure(
          _cells[cell] ??= StructureElement(
            placed.header ? 'TH' : 'TD',
            attributes: {
              if (placed.header) 'Scope': '/Column',
              // (A cell spanning rows or columns says so: PDF/UA-1 7.2
              // counts each row's columns with them.)
              if (cell.rowSpan > 1) 'RowSpan': '${cell.rowSpan}',
              if (cell.colSpan > 1) 'ColSpan': '${cell.colSpan}',
            },
          ),
        );
      paint();
      canvas
        ..endStructure()
        ..endStructure();
    }

    void border(_PlacedCell placed) {
      structure?.beginArtifact();
      _paintBorder(painter, placed, x, top);
      structure?.endArtifact();
    }

    if (borders == TableBorders.withCells) {
      for (final placed in cells) {
        border(placed);
        content(placed);
      }
      return;
    }
    cells
      ..forEach(content)
      ..forEach(border);
  }

  /// Paints the border of [placed] (its decoration, if it has one).
  void _paintBorder(
    _Painter painter,
    _PlacedCell placed,
    double x,
    double top,
  ) {
    final canvas = painter.canvas;
    {
      if (placed.cell.decoration case final decoration?) {
        decoration(
          painter.page,
          Rect(
            x + placed.x,
            top - placed.y - placed.height,
            placed.width,
            placed.height,
          ),
          first: !placed.cell._openTop,
          last: !placed.openBottom,
        );
        return;
      }
      final border = placed.cell.border;
      final widths = border.widths;
      if (widths == EdgeInsets.zero) return;
      final l = x + placed.x;
      final r = l + placed.width;
      final t = top - placed.y;
      final b = t - placed.height;
      canvas
        ..save()
        ..setStrokeColor(border.color);
      void side(double w, double x1, double y1, double x2, double y2) {
        if (w <= 0) return;
        canvas
          ..setLineWidth(w)
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..stroke();
      }

      // Borders are centered on the cell's edges, and the horizontal ones
      // reach over the vertical ones' halves at the corners.
      if (!placed.cell._openTop) {
        side(widths.top, l - widths.left / 2, t, r + widths.right / 2, t);
      }
      if (!placed.openBottom) {
        side(widths.bottom, l - widths.left / 2, b, r + widths.right / 2, b);
      }
      side(widths.left, l, b, l, t);
      side(widths.right, r, b, r, t);
      canvas.restore();
    }
  }
}
