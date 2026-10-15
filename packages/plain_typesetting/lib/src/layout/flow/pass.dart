part of '../flow.dart';

// One layout of the content: regions filled with boxes, page by page.

/// One layout of the content.
final class _Pass {
  new(this.layout, this.previous);

  final FlowLayout layout;

  /// The anchors of the previous pass (for page references).
  final Map<String, AnchorPosition> previous;

  final List<_Page> pages = [];

  /// How the lines of the page being filled run: an image on a vertical
  /// page is laid out turned, to stand upright on it.
  WritingMode writingMode = WritingMode.horizontal;

  final Map<String, AnchorPosition> anchors = {};

  /// The first and last page (1-based) of each tagged box.
  final Map<String, ({int first, int last})> tagPages = {};

  /// The lines of the paragraphs with page references, by box and width
  /// (resolved for this pass).
  final Map<(ParagraphBox, double), List<Line>> _lines = {};

  bool hasReferences = false;

  final List<_Boundary> boundaries = [];

  /// The pages (0-based) of the anchors placed more than once, after the
  /// first.
  final Map<String, List<int>> repeatedAnchors = {};

  /// The layout this pass goes on from, and the pages of it that change
  /// (null: all after where it goes on).
  LayoutResult? _reuse;

  Set<int>? _changedPages;

  /// The boundaries of [_reuse] by their box.
  Map<int, (int, _Boundary)> _reuseBoundaries = const {};

  /// The pages taken from [_reuse] (their marks are in them already).
  final Set<int> _kept = {};

  /// Lays [content] out from [boundary] of [reuse] (of the same content
  /// up to it): its pages before the boundary, then the rest, taking its
  /// pages again from a later boundary on when the pass comes to it as
  /// [reuse] did and none of them is in [changedPages].
  void resume(
    List<LayoutBox> content,
    LayoutResult reuse,
    _Boundary boundary,
    Set<int>? changedPages,
  ) {
    _reuse = reuse;
    _changedPages = changedPages;
    if (changedPages != null) {
      _reuseBoundaries = {
        for (final (i, b) in reuse._boundaries.indexed) b.index: (i, b),
      };
    }
    pages.addAll(reuse._pages.take(boundary.pages));
    _kept.addAll(Iterable.generate(boundary.pages));
    _notesSet.addAll(boundary.notesSet);
    _floatsSet.addAll(boundary.floatsSet);
    hasReferences = boundary.hasReferences;
    boundaries.addAll(
      reuse._boundaries.takeWhile((b) => b.index <= boundary.index),
    );
    run(content, from: boundary);
  }

  /// A page of the template named [name], as the page after [pages].
  _Page _newPage(String? name) {
    final template = layout.templates[name] ?? layout.templates[null]!;
    return _Page(
      layout.templateForPage?.call(template, pages.length + 1) ?? template,
    );
  }

  /// Adds [page], with what [carried] holds placed at its top.
  void _add(_Page page, List<_Placed> carried) {
    if (carried.isNotEmpty) {
      final region = page.template.regions.first;
      page.placed.insertAll(0, [
        for (final placed in carried) (region, placed),
      ]);
      carried.clear();
    }
    pages.add(page);
  }

  void run(List<LayoutBox> content, {_Boundary? from}) {
    LayoutBox? rest = from == null
        ? BlockBox(content)
        : from.index < content.length
        ? BlockBox._rest(content.sublist(from.index), const BoxStyle())
        : null;
    var template = from == null ? layout.startTemplate : from.template;
    var guard = 0;
    // What was placed on a page that was replaced (anchors, marks: it had
    // no height), carried to the page replacing it.
    final carried = <_Placed>[];
    // Notes deferred past the end of the content go on on pages of their
    // own.
    // Floating boxes that didn't fit, for the top of the next region.
    final floats = <LayoutBox>[];
    // What is left of blocks floating to a side, for the top of the next
    // region.
    var carriedFloats = <LayoutBox>[];
    // Floating boxes that span a page's columns, for the top of the next
    // page across them (as LaTeX's `figure*`).
    final spans = <LayoutBox>[];
    while (rest != null ||
        spans.isNotEmpty ||
        _deferredNotes != null ||
        floats.isNotEmpty ||
        carriedFloats.isNotEmpty) {
      final page = _newPage(template);
      writingMode = page.template.writingMode;
      if (!layout.keepTemplate) template = null;
      var discard = false;
      PageSide? side;
      var regions = page.template.regions;
      // (Page columns: the floating boxes that span them, across the top
      // of the page, the columns under them.)
      final paged = regions.length > 1;
      if (paged) {
        spans.addAll([
          for (final float in floats)
            if (float.style.floatSpan &&
                float.style.float != FloatPlacement.bottom)
              float,
        ]);
        floats.removeWhere(spans.contains);
      }
      if (paged && spans.isNotEmpty) {
        final left = regions.first.left;
        final width = regions.last.right - left;
        final spanned = _place(
          BlockBox([for (final span in spans) ..._cleared(span, top: true)]),
          width,
          regions.first.height,
          atTop: true,
        );
        spans.clear();
        final height = spanned.height;
        page.placed.add((
          Rect(left, regions.first.top - height, width, height),
          spanned.placed,
        ));
        regions = [
          for (final region in regions)
            Rect(
              region.left,
              region.bottom,
              region.width,
              math.max(0, region.height - height),
            ),
        ];
      }
      for (final (i, region) in regions.indexed) {
        _regionHeight = region.height;
        // Floating boxes that waited: at the top of the region, those for
        // the bottom at its bottom.
        final waitingBottom = [
          for (final float in floats)
            if (float.style.float == FloatPlacement.bottom)
              ..._cleared(float, top: false),
        ];
        // (The others at the top, the content starting below them as at
        // the region's top.)
        var waitingTop = [
          for (final float in floats)
            if (float.style.float != FloatPlacement.bottom)
              ..._cleared(float, top: true),
        ];
        final restBox = rest ?? const BlockBox([]);
        // A break the floating boxes waited before: after them, in the
        // flow.
        bool startsWithBreak(LayoutBox box) => switch (box) {
          BreakBox() => true,
          BlockBox(:final children) when children.isNotEmpty => startsWithBreak(
            children.first,
          ),
          _ => false,
        };
        final breakFirst = waitingTop.isNotEmpty && startsWithBreak(restBox);
        final content = breakFirst
            ? BlockBox([...waitingTop, restBox])
            : restBox;
        if (breakFirst) waitingTop = const [];
        floats.clear();
        _floatsWaiting = 0;
        _floatsNotHere.clear();
        final reservedTop = waitingTop.isEmpty
            ? 0.0
            : _place(
                BlockBox(waitingTop),
                region.width,
                double.infinity,
                atTop: true,
              ).height;
        final reserved =
            (waitingBottom.isEmpty
                ? 0.0
                : _measure(BlockBox(waitingBottom), region.width)) +
            reservedTop;
        // What is left of blocks floating to a side: at the top of the
        // region first, the content going around them.
        _seedExclusions = [];
        final carriedHere = carriedFloats;
        carriedFloats = [];
        // (Their pieces set here: the notes they refer to are the region's.)
        final beside = <_Placed>[];
        for (final float in carriedHere) {
          final side = float.style.side!;
          final width = math.min(float.style.sideWidth, region.width);
          var floatTop = 0.0;
          for (final other in _seedExclusions) {
            if (other.side == side) {
              floatTop = math.max(floatTop, other.bottom);
            }
          }
          final floatFit = floatTop.isInfinite
              ? null
              : _withoutExclusions(
                  () => _offGrid(
                    () => _place(
                      _unsided(float),
                      width,
                      region.height - reserved - floatTop,
                      atTop: true,
                    ),
                  ),
                );
          if (floatFit?.placed case final piece?) {
            beside.add(piece);
            final x = side == FloatSide.right ? region.width - width : 0.0;
            page.placed.add((
              Rect(
                region.left + x,
                region.bottom,
                width,
                region.height - floatTop,
              ),
              piece,
            ));
            _seedExclusions.add(
              _Exclusion(
                side,
                x,
                x + width,
                gap: float.style.sideGap,
                top: floatTop,
                bottom: floatFit!.rest == null
                    ? floatTop + floatFit.height
                    : double.infinity,
              ),
            );
            if (floatFit.rest case final more?) {
              carriedFloats.add(_sided(more, float.style));
            }
          } else {
            carriedFloats.add(float);
          }
        }
        var fit = _placeRegion(
          content,
          region.width,
          region.height - reserved,
          below: reservedTop,
        );
        // (Page columns: a floating box that spans them waits for the top
        // of the next page, the column placed again without it.)
        if (paged && fit.pinned.any((pin) => pin.$1.style.floatSpan)) {
          for (final (box, _, _) in fit.pinned) {
            if (box.style.floatSpan && _floatsSet.add(box)) spans.add(box);
          }
          _floatsWaiting = 0;
          _floatsReached.clear();
          fit = _placeRegion(
            content,
            region.width,
            region.height - reserved,
            below: reservedTop,
          );
        }
        // Floating boxes that fit, at the top or the bottom of the region:
        // the content in what the top ones leave.
        final top = <LayoutBox>[...waitingTop];
        final bottom = <LayoutBox>[...waitingBottom];
        final pinnedBottom = Map<LayoutBox, List<LayoutBox>>.identity();
        if (fit.pinned.isNotEmpty) {
          fit = _pinFloats(
            content,
            region,
            fit,
            top,
            bottom,
            pinnedBottom: pinnedBottom,
          );
        }
        final topFit = top.isEmpty
            ? null
            : _place(BlockBox(top), region.width, region.height, atTop: true);
        final topHeight = topFit?.height ?? 0.0;
        final area = topHeight == 0
            ? region
            : Rect(
                region.left,
                region.bottom,
                region.width,
                region.height - topHeight,
              );
        if (topFit != null) {
          page.placed.add((
            Rect(
              region.left,
              region.bottom + area.height,
              region.width,
              topHeight,
            ),
            topFit.placed,
          ));
        }
        if (layout.notes.isNotEmpty ||
            _deferredNotes != null ||
            bottom.isNotEmpty) {
          final (withNotes, notes) = _notes(
            content,
            area,
            fit,
            bottom: bottom,
            above: top,
            pinnedBottom: pinnedBottom,
            beside: beside,
          );
          fit = withNotes;
          page.placed.add((area, fit.placed));
          if (notes != null) {
            page.placed.add((
              Rect(area.left, area.bottom, area.width, notes.height),
              notes.placed,
            ));
            if (notes.height > 0) {
              final top = area.bottom + notes.height;
              page.notesTop = math.max(page.notesTop ?? top, top);
            }
          }
        } else {
          page.placed.add((area, fit.placed));
        }
        rest = fit.rest;
        floats
          ..addAll(fit.floated)
          ..addAll(_bottomCarried);
        _bottomCarried.clear();
        carriedFloats.addAll(fit.carried);
        if (rest == null &&
            _deferredNotes == null &&
            floats.isEmpty &&
            spans.isEmpty &&
            carriedFloats.isEmpty) {
          break;
        }
        if (fit.hit case BreakBox(
          kind: BreakKind.page,
          template: final name,
          side: final wanted,
        )) {
          side = wanted;
          if (name != null || !layout.keepTemplate) template = name;
          // A break to another template on a page still empty replaces it.
          discard =
              layout.keepTemplate &&
              name != null &&
              i == 0 &&
              (fit.placed?.height ?? 0) == 0;
          break;
        }
      }
      if (discard) {
        carried.addAll([for (final (_, placed) in page.placed) ?placed]);
      } else {
        _add(page, carried);
      }
      // A break to a side: a blank page first when the next page is on
      // the other side.
      if (side != null && PageSide.of(pages.length + 1) != side) {
        _add(_newPage(template), carried);
      }
      // A clean boundary: the rest is the top-level boxes from one on,
      // nothing pending.
      if (carried.isEmpty &&
          floats.isEmpty &&
          spans.isEmpty &&
          _deferredNotes == null) {
        if (rest case BlockBox(:final children, _continued: true)
            when children.isNotEmpty &&
                children.length < content.length &&
                identical(
                  children.first,
                  content[content.length - children.length],
                )) {
          var boundary = _Boundary(
            index: content.length - children.length,
            pages: pages.length,
            template: template,
            notesSet: {..._notesSet},
            floatsSet: Set.identity()..addAll(_floatsSet),
            hasReferences: hasReferences,
          );
          boundaries.add(boundary);
          // The pages of the layout gone on from, up to its next
          // boundary, when this one is the same as its and none of them
          // changes.
          while (true) {
            final (i, old) = _reuseBoundaries[boundary.index] ?? (-1, null);
            if (old == null || !old.sameAs(boundary)) break;
            final reuse = _reuse!;
            final next = i + 1 < reuse._boundaries.length
                ? reuse._boundaries[i + 1]
                : null;
            final end = next?.pages ?? reuse._pages.length;
            if (_changedPages!.any((p) => p >= old.pages && p < end)) break;
            for (final page in reuse._pages.sublist(old.pages, end)) {
              _kept.add(pages.length);
              pages.add(page);
            }
            if (next == null) {
              rest = null;
              break;
            }
            rest = BlockBox._rest(
              content.sublist(next.index),
              const BoxStyle(),
            );
            template = next.template;
            _notesSet
              ..clear()
              ..addAll(next.notesSet);
            _floatsSet
              ..clear()
              ..addAll(next.floatsSet);
            boundaries.add(boundary = next);
          }
        }
      }
      if (++guard > 100000) throw StateError('layout does not progress');
    }
    // A last page with nothing on it (after a trailing page break) is left
    // out.
    if (pages.length > 1 &&
        pages.last.placed.every((p) => (p.$2?.height ?? 0) == 0)) {
      pages.removeLast();
    }
    for (final (i, page) in pages.indexed) {
      final kept = _kept.contains(i);
      for (final (region, placed) in page.placed) {
        placed?.visit(
          region.left,
          region.top,
          (anchor, x, y) {
            if (anchors.containsKey(anchor)) {
              (repeatedAnchors[anchor] ??= []).add(i);
            } else {
              anchors[anchor] = AnchorPosition(i, x, y);
            }
          },
          // (Pages kept from another pass have their marks.)
          kept ? (_) {} : page.marks.add,
          (tag) {
            final first = tagPages[tag]?.first ?? i + 1;
            tagPages[tag] = (first: first, last: i + 1);
          },
        );
      }
    }
    _placeSideNotes();
  }

  /// The side notes that could not be set: the column of a page was too
  /// small for them, or no page has one.
  final List<String> unsetSideNotes = [];

  /// The notes whose anchors were placed (each set once).
  final Set<String> _notesSet = {};

  /// The number of the region each note's reference was placed in (of
  /// those [_notes] counted), for [FlowLayout.notesLag].
  final Map<LayoutBox, int> _noteRegion = Map.identity();

  /// How many regions [_notes] has set the notes of.
  int _noteRegions = 0;

  /// Floating boxes for a region's bottom that [_notes] found no room for
  /// whole: for the next region's bottom.
  final List<LayoutBox> _bottomCarried = [];

  /// The notes that didn't fit in the region before: the main series'
  /// (with the floating boxes at the bottom), and each stream's, to go
  /// first in its own place (under its separator, in its columns).
  _WaitingNotes? _deferredNotes;

  /// The anchors [placed] reports, in order.
  static List<String> _anchorsOf(_Placed? placed) {
    final names = <String>[];
    placed?.visit(0, 0, (name, _, _) => names.add(name), (_) {}, (_) {});
    return names;
  }

  /// The label of the page of [anchor] from the previous pass.
  String? _pageOf(String anchor) => switch (previous[anchor]) {
    AnchorPosition(:final page) => layout.pageLabel(page + 1),
    null => null,
  };

  List<Line> _linesOf(ParagraphBox box, double width) {
    final source = box._source ?? box;
    final breaker = source.lineBreaker ?? layout.lineBreaker;
    List<Line> lines() => switch ((source._items, breaker)) {
      (final items?, final ItemLineBreaker breaker) =>
        breaker
            .breakItemLines(_resolve(source.paragraph), items, (_) => width)
            .lines,
      _ => breaker.breakLines(_resolve(source.paragraph), (_) => width),
    };
    if (_hasReferences(source.paragraph)) {
      return _lines[(source, width)] ??= lines();
    }
    return (layout._lines[source] ??= {})[width] ??= lines();
  }

  /// [box] as it goes on at [width]: the rest of a paragraph whose lines
  /// were broken at another width becomes its items after them, broken
  /// again (as a paragraph beside a block floating to a side goes on
  /// below it).
  ParagraphBox _reflowedAt(ParagraphBox box, double width) {
    final at = box._width;
    if (box._from == 0 || at == null || (at - width).abs() < 1e-9) return box;
    return _reflowed(box, at) ?? box;
  }

  /// The rest of [box] (its lines from its first on, broken at [width])
  /// as its items, to be broken again; null where its breaker doesn't
  /// break items.
  ParagraphBox? _reflowed(ParagraphBox box, double width) {
    final source = box._source ?? box;
    final breaker = source.lineBreaker ?? layout.lineBreaker;
    if (breaker is! ItemLineBreaker) return null;
    final paragraph = _resolve(source.paragraph);
    // (One with a first line of its own style isn't broken again.)
    if (paragraph.firstLineContent != null && source._items == null) {
      return null;
    }
    final items =
        source._items ??
        paragraphItems(
          paragraph,
          maxWidth: paragraph.breakLongWords
              ? width - paragraph.firstLineIndent
              : null,
        );
    if (box._from == 0) {
      return source._items != null
          ? box
          : ParagraphBox._reflowed(box, items, first: true);
    }
    final breaks = breaker
        .breakItemLines(paragraph, items, (_) => width)
        .breaks;
    if (box._from > breaks.length) return null;
    return ParagraphBox._reflowed(
      box,
      items.sublist(breaks[box._from - 1] + 1),
      after: box._from,
    );
  }

  static bool _hasReferences(Paragraph paragraph) =>
      paragraph.content.any((c) => c is PageReference);

  /// [paragraph] with its page references filled in.
  Paragraph _resolve(Paragraph paragraph) {
    if (!_hasReferences(paragraph)) return paragraph;
    hasReferences = true;
    return paragraph.copyWith(
      content: [
        for (final c in paragraph.content)
          if (c case PageReference(:final anchor, :final placeholder))
            c.resolve(_pageOf(anchor) ?? placeholder)
          else
            c,
      ],
    );
  }

  /// The space the last of [children] leaves below the content: its
  /// margin below (and, through a block with nothing closing it, its own
  /// last child's), or a spacer's height.
  double _trailingSpace(List<LayoutBox> children) {
    if (children.isEmpty) return 0;
    final last = children.last;
    return switch (last) {
      SpacerBox(:final height) =>
        height + _trailingSpace(children.sublist(0, children.length - 1)),
      BlockBox(:final children, :final style)
          when style.padding.bottom == 0 && style.border.widths.bottom == 0 =>
        style.margin.bottom + _trailingSpace(children),
      _ => last.style.margin.bottom,
    };
  }

  /// The height of [box] laid out with no limit (beside no block floating
  /// to a side).
  double _measure(LayoutBox box, double width, {bool atTop = false}) {
    // (A grid's origin is set by what is placed, not measured.)
    final origin = _gridOrigin;
    try {
      return _withoutExclusions(
        () => _place(box, width, double.infinity, atTop: atTop),
      ).height;
    } finally {
      _gridOrigin = origin;
    }
  }

  /// The least height [box] needs where it starts (to keep a box with
  /// it).
  double _minHeight(LayoutBox box, double width) {
    final margin = box.style.margin;
    // A block kept together starts whole, when a region holds it.
    if (box is BlockBox && box.style.keepTogether) {
      final whole = _measure(box, width);
      if (whole <= _regionHeight + 1e-6) return whole;
    }
    switch (box) {
      case ParagraphBox(:final orphans):
        // (The rest of one from the line it goes on with.)
        final rest = _reflowedAt(box, width - margin.horizontal);
        final lines = _linesOf(rest, width - margin.horizontal);
        return (rest._from > 0 || rest._continuation ? 0 : margin.top) +
            lines
                .skip(rest._from)
                .take(orphans)
                .fold(0, (sum, line) => sum + line.height);
      case BlockBox(:final children) || ColumnsBox(:final children):
        final style = box.style;
        var inner =
            width -
            margin.horizontal -
            style.border.widths.horizontal -
            style.padding.horizontal;
        // (A column set's first box in a column's width.)
        if (box case ColumnsBox(:final count, :final gap)) {
          inner = (inner - gap * (count - 1)) / count;
        }
        return margin.top +
            style.border.widths.top +
            style.padding.top +
            (children.isEmpty ? 0 : _minHeight(children.first, inner));
      // A table splits after its first row (its header repeated): that
      // much of it, unless it is kept together.
      case TableBox(:final rows, :final headerRows)
          when box._grid == null &&
              !box.style.keepTogether &&
              rows.length > headerRows + 1:
        return _measure(
          TableBox(
            rows.sublist(0, headerRows + 1),
            columns: box.columns,
            headerRows: headerRows,
            width: box.width,
            shrinkToContent: box.shrinkToContent,
            align: box.align,
            stripes: box.stripes,
            cellsContainMargins: box.cellsContainMargins,
            style: box.style,
          ),
          width,
        );
      case ImageBox() ||
          DrawingBox() ||
          TableBox() ||
          UprightBox() ||
          VerticalBox() ||
          MirroredBox():
        return _measure(box, width);
      case CustomBox(:final content):
        return margin.top + content.minHeight(width - margin.horizontal);
      case SpacerBox() || BreakBox():
        return 0;
    }
  }

  _Fit _place(
    LayoutBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    // (A box that goes on a line of the grid: its first line does.)
    if (box.style.gridLine case final line? when !_isContinued(box)) {
      _gridLine = line;
    }
    return _tagged(
      box.style.structure,
      _placeBox(box, width, available, atTop: atTop),
    );
  }

  /// [fit] with what it placed painted as [element]'s content, if any.
  static _Fit _tagged(StructureElement? element, _Fit fit) {
    if (element == null) return fit;
    final placed = fit.placed;
    if (placed == null) return fit;
    return _Fit(
      _PlacedTagged(element, placed),
      fit.height,
      fit.rest,
      hit: fit.hit,
      floated: fit.floated,
      pinned: fit.pinned,
      carried: fit.carried,
    );
  }

  _Fit _placeBox(
    LayoutBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    return switch (box) {
      // Nothing floats out of a framed block (padded, bordered, filled or
      // decorated): it stays in its frame.
      BlockBox(:final style)
          when style.padding != EdgeInsets.zero ||
              style.border != Border.none ||
              style.background != null ||
              style.decoration != null =>
        _withoutFloats(() => _block(box, width, available, atTop: atTop)),
      BlockBox() => _block(box, width, available, atTop: atTop),
      ParagraphBox() => _paragraph(
        _reflowedAt(box, width - box.style.margin.horizontal),
        width,
        available,
        atTop: atTop,
      ),
      ImageBox() => _image(box, width, available, atTop: atTop),
      DrawingBox() => _drawing(box, width, available, atTop: atTop),
      SpacerBox(:final height) =>
        atTop
            ? const _Fit(_PlacedSpace(0), 0, null)
            : _Fit(
                _PlacedSpace(math.min(height, available)),
                math.min(height, available),
                null,
              ),
      BreakBox() => _Fit(const _PlacedSpace(0), 0, null, hit: box),
      ColumnsBox() => _withoutFloats(() {
        _columnsDepth++;
        try {
          return _columns(box, width, available, atTop: atTop);
        } finally {
          _columnsDepth--;
        }
      }),
      TableBox() => _withoutFloats(
        () => _table(box, width, available, atTop: atTop),
      ),
      CustomBox() => _custom(box, width, available, atTop: atTop),
      UprightBox() => _upright(box, width, available, atTop: atTop),
      VerticalBox() => _turned(box, width, available, atTop: atTop),
      MirroredBox() => _mirrored(box, width, available, atTop: atTop),
    };
  }

  _Fit _block(
    BlockBox box,
    double width,
    double available, {
    required bool atTop,
  }) {
    // (Where it starts, as measuring below may move it.)
    final (y, left, right) = (_y, _left, _right);
    final style = box.style;
    final continued = box._continued;
    final clone = style.cloneEdges;
    final top =
        (atTop || continued ? 0.0 : style.margin.top) +
        (continued && !clone ? 0 : style.border.widths.top + style.padding.top);
    final bottom = style.padding.bottom + style.border.widths.bottom;
    final inner =
        width -
        style.margin.horizontal -
        style.border.widths.horizontal -
        style.padding.horizontal;
    if (style.keepTogether && !atTop && !continued && available.isFinite) {
      final whole = _measure(box, width);
      final region = _regionHeight;
      if (layout.pageBreaker.moveKeptBox(whole, available, region)) {
        return _Fit.moved(box);
      }
    }
    // A block aligned in the room of its region: the room above it as its
    // top margin, when it fits whole.
    if (style.verticalAlign case final align?
        when align != VerticalAlign.top &&
            atTop &&
            !continued &&
            available.isFinite) {
      // (Its margin below is outside it, and the space its last child
      // leaves below, as CSS's margins collapse through a container's
      // end.)
      final whole =
          _measure(BlockBox(box.children, style: style._lowered(0)), width) -
          style.margin.bottom -
          _trailingSpace(box.children);
      if (whole < available) {
        final room =
            (available - whole) * (align == VerticalAlign.middle ? .5 : 1);
        return _block(
          BlockBox(box.children, style: style._lowered(room)),
          width,
          available,
          atTop: false,
        );
      }
    }
    // The bottom padding and border close the block: a page break inside
    // it reserves no room for them, they need room only below its last
    // child (if they don't fit there, the block is placed again with room
    // for them throughout).
    // (A block whose pieces each close reserves the room throughout.)
    final full = available - top - (clone ? bottom : 0);
    final mark = _exclusions.length;
    _y = y;
    _left = left;
    _right = right;
    final fit = _blockChildren(
      box,
      width,
      inner,
      full,
      top,
      atTop: atTop,
      reserved: clone,
    );
    // (The margin below as placed: no more than the room left.)
    final marginPlaced = switch (fit.placed) {
      _PlacedBlock(:final marginBottom?) => marginBottom,
      _ => style.margin.bottom,
    };
    if (!clone &&
        fit.rest == null &&
        fit.hit == null &&
        bottom > 0 &&
        fit.height - marginPlaced > available + 1e-6) {
      _exclusions.length = mark;
      _y = y;
      _left = left;
      _right = right;
      return _blockChildren(
        box,
        width,
        inner,
        full - bottom,
        top,
        atTop: atTop,
        reserved: true,
      );
    }
    return fit;
  }

  /// [box]'s children placed in [room] below [top]: the block split where
  /// they don't fit, else the whole block.
  _Fit _blockChildren(
    BlockBox box,
    double width,
    double inner,
    double room,
    double top, {
    required bool atTop,
    bool reserved = false,
  }) {
    final style = box.style;
    final continued = box._continued;
    final bottom = style.padding.bottom + style.border.widths.bottom;
    final children = <(double, _Placed)>[];
    final floated = <LayoutBox>[];
    final pinned = <(LayoutBox, double, double)>[];
    final carried = <LayoutBox>[];
    var cursor = 0.0;
    var trailing = 0.0;
    final atTopInside = atTop && top == 0 && !box._containsMargins;
    // Where the content starts in the region, for blocks floating to a
    // side; the blocks floating there before the children.
    final contentY = _y + top;
    final innerLeft =
        _left +
        style.margin.left +
        style.border.widths.left +
        style.padding.left;
    final innerRight =
        _right +
        style.margin.right +
        style.border.widths.right +
        style.padding.right;
    final entryMark = _exclusions.length;
    // [rest] from child [from] on (placed in part when [partial]): the
    // repeated head first when a child after it was placed.
    _Fit split(
      List<LayoutBox> rest, {
      BreakBox? hit,
      int? from,
      bool partial = false,
      bool headOnly = false,
    }) {
      if (children.isEmpty &&
          floated.isEmpty &&
          rest.length == box.children.length &&
          !atTop) {
        _exclusions.length = entryMark;
        return _Fit.moved(box);
      }
      // A break in its repeated head, or right after it with nothing of
      // what follows placed: the head kept whole and with what follows it,
      // the block moved to the next region (once: a head that doesn't fit
      // there with what follows it either, as one taller than a region, is
      // not repeated, as a table's header rows taller than a page).
      final inHead =
          box.repeatedHead > 0 &&
          !headOnly &&
          rest.isNotEmpty &&
          from != null &&
          (partial ? from < box.repeatedHead : from <= box.repeatedHead);
      if (inHead &&
          hit == null &&
          !atTop &&
          floated.isEmpty &&
          pinned.isEmpty &&
          carried.isEmpty &&
          _headsMoved.add(box)) {
        _exclusions.length = entryMark;
        return _Fit.moved(box);
      }
      final head = inHead ? 0 : box.repeatedHead;
      final repeat =
          head > 0 &&
          (rest.isNotEmpty || headOnly) &&
          from != null &&
          (partial ? from >= head : from > head);
      // (The space below the last piece placed doesn't carry to the
      // region's end: a piece with its own bottom edge closes right
      // under it.)
      // (A piece the region's end cuts off reaches it when the style
      // says so.)
      final toEnd =
          style.splitToRegionEnd &&
          (rest.isNotEmpty || repeat) &&
          room.isFinite;
      final placed = _PlacedBlock(
        style,
        width,
        // ([room] has the bottom edge's room taken out when [reserved].)
        toEnd
            ? top + room + (reserved ? bottom : 0)
            : top +
                  cursor -
                  (style.cloneEdges ? trailing : 0) +
                  (style.cloneEdges ? bottom : 0),
        children,
        top: atTop || continued ? 0 : style.margin.top,
        openTop: continued,
        openBottom: true,
        marks: continued ? const {} : style.marks,
        anchor: continued ? null : style.anchor,
      );
      return _Fit(
        placed,
        placed.height,
        // A box that ends with a break ends there: nothing of it (not
        // its bottom margin) is carried past the break.
        rest.isEmpty && !repeat
            ? null
            : BlockBox._rest(
                [if (repeat) ...box.children.take(head), ...rest],
                style,
                repeatedHead: head,
                containsMargins: box._containsMargins,
              ),
        hit: hit,
        floated: floated,
        pinned: pinned,
        carried: carried,
      );
    }

    // (A paragraph set around blocks floating to a side goes on as its
    // rest, in its place.)
    final kids = [...box.children];
    for (var i = 0; i < kids.length; i++) {
      final child = kids[i];
      // A floating box set at the top or bottom of a region already.
      if (_floatsSet.contains(child)) {
        _floatsReached.add(child);
        continue;
      }
      final childAtTop = atTopInside && cursor == 0;
      if (child is BreakBox) {
        // With floating boxes waiting (or the rest of one floating to a
        // side), the break comes after them: the region ends here, the
        // break left for after them.
        if (floated.isNotEmpty || _floatsWaiting > 0 || carried.isNotEmpty) {
          return split(kids.sublist(i), from: i);
        }
        // A break at the top of a region: none, unless forced (or a break
        // to a template, which replaces an empty page).
        if (childAtTop &&
            !child.force &&
            (child.template == null || !layout.keepTemplate) &&
            (child.side == null ||
                PageSide.of(pages.length + 1) == child.side)) {
          continue;
        }
        final rest = kids.sublist(i + 1);
        return split(rest, hit: child, from: i + 1);
      }
      // A box no floating box may pass: after them, in the next region.
      if (child.style.floatBarrier &&
          !childAtTop &&
          (floated.isNotEmpty || _floatsWaiting > 0)) {
        return split(kids.sublist(i), from: i);
      }
      // A floating box this region's text no longer reaches (see
      // [_pinFloats]): for the next region.
      if (_floatsNotHere.contains(child) && _floats(child)) {
        floated.add(child);
        _floatsWaiting++;
        continue;
      }
      // A floating box that spans the columns it's in: for the region's
      // top or bottom, measured there (not placed in its column).
      if (child.style.floatSpan &&
          _floatDepth > 0 &&
          _floats(child) &&
          child.style.float != null &&
          child.style.float != FloatPlacement.next) {
        pinned.add((child, top + cursor, 0));
        continue;
      }
      final mark = _exclusions.length;
      final y = contentY + cursor;
      _y = y;
      _left = innerLeft;
      _right = innerRight;
      // A block floating to a side: set there, the blocks after it beside
      // it; what doesn't fit, at the top of the next region.
      if (child.style.side case final side? when _excluding) {
        final left = innerLeft;
        final right = _regionWidth - innerRight;
        final width = math.min(child.style.sideWidth, right - left);
        // (Under one already floating to that side.)
        var floatTop = y;
        for (var moved = true; moved;) {
          moved = false;
          for (final other in _exclusions) {
            if (other.side == side &&
                other.top <= floatTop + 1e-6 &&
                other.bottom > floatTop + 1e-6) {
              floatTop = other.bottom;
              moved = true;
            }
          }
        }
        final floatRoom = room - cursor - (floatTop - y);
        final x = side == FloatSide.right ? right - width : left;
        final floatFit = floatTop.isInfinite || floatRoom <= 0
            ? null
            : _offGrid(
                () => _withoutExclusions(
                  () => _place(_unsided(child), width, floatRoom, atTop: false),
                ),
              );
        // (In a column, one that doesn't fit whole in the room left goes
        // on in the next column, and one taller than a column is set in
        // the flow: a column carries nothing to the next region.)
        final inFlow =
            _inColumn && (floatFit?.placed == null || floatFit!.rest != null);
        if (!inFlow) {
          if (floatFit?.placed case final piece?) {
            children.add((
              cursor + floatTop - y,
              _PlacedBlock(
                BoxStyle(margin: EdgeInsets(left: x - left)),
                inner,
                floatFit!.height,
                [(0, piece)],
                top: 0,
                openTop: false,
                openBottom: false,
                marks: const {},
                anchor: null,
              ),
            ));
            _exclusions.add(
              _Exclusion(
                side,
                x,
                x + width,
                gap: child.style.sideGap,
                top: floatTop,
                bottom: floatFit.rest == null
                    ? floatTop + floatFit.height
                    : double.infinity,
                shape: child.style.sideShape,
              ),
            );
            if (floatFit.rest case final rest?) {
              carried.add(_sided(rest, child.style));
            }
          } else {
            carried.add(child);
          }
          continue;
        }
        if (!childAtTop) {
          _exclusions.length = mark;
          return split(kids.sublist(i), from: i);
        }
        kids[i] = _unsided(child);
        i--;
        continue;
      }
      // Beside blocks floating to a side: a block that fits beside them
      // whole is set there, narrowed; one that doesn't, below them (a
      // block without a frame, its children each so).
      var fit = _Fit.moved(child);
      var placed = false;
      if (_excluding && _exclusions.isNotEmpty && !_transparent(child)) {
        final left = innerLeft;
        final right = _regionWidth - innerRight;
        var narrowLeft = left;
        var narrowRight = right;
        var until = double.infinity;
        for (final other in _exclusions) {
          if (other.top > y + 1e-6 || other.bottom <= y + 1e-6) continue;
          final before = (narrowLeft, narrowRight);
          if (other.side == FloatSide.right) {
            narrowRight = math.min(narrowRight, other.left - other.gap);
          } else {
            narrowLeft = math.max(narrowLeft, other.right + other.gap);
          }
          if ((narrowLeft, narrowRight) != before) {
            until = math.min(until, other.bottom);
          }
        }
        // A paragraph beside an outline (an image's shape): set line by
        // line in the room it leaves, the rest below.
        if (_aroundShapes(child, left, right, y, room - cursor) case (
          final piece,
          final height,
          final rest,
        )) {
          children.add((cursor, piece));
          cursor += height;
          trailing = rest == null ? child.style.margin.bottom : 0;
          if (rest != null) {
            kids[i] = rest;
            i--;
          }
          continue;
        }
        if (narrowLeft > left + 1e-6 || narrowRight < right - 1e-6) {
          // (A block reaching out past its edges with negative margins
          // reaches no nearer the floating block than the gap.)
          final margin = child.style.margin;
          final narrowed = BlockBox(
            [child],
            style: BoxStyle(
              margin: EdgeInsets(
                left:
                    narrowLeft -
                    left +
                    (narrowLeft > left + 1e-6
                        ? math.max(0.0, -margin.left)
                        : 0.0),
                right:
                    right -
                    narrowRight +
                    (narrowRight < right - 1e-6
                        ? math.max(0.0, -margin.right)
                        : 0.0),
              ),
            ),
          );
          final tried = _place(
            narrowed,
            inner,
            room - cursor,
            atTop: childAtTop,
          );
          final beside =
              tried.placed != null &&
              (until.isInfinite ||
                  (tried.rest == null &&
                      tried.hit == null &&
                      tried.height - child.style.margin.bottom <=
                          until - y + 1e-6));
          if (beside) {
            fit = tried;
            placed = true;
          } else if (_runaround(child, narrowRight - narrowLeft, until - y)
              case (final piece, final height, final rest)) {
            // A paragraph that doesn't fit beside them whole: its first
            // lines beside them, the rest in its place, set again at the
            // full width below them (a runaround).
            children.add((
              cursor,
              narrowLeft > left + 1e-6
                  ? _PlacedBlock(
                      BoxStyle(margin: EdgeInsets(left: narrowLeft - left)),
                      inner,
                      height,
                      [(0, piece)],
                      top: 0,
                      openTop: false,
                      openBottom: false,
                      marks: const {},
                      anchor: null,
                    )
                  : piece,
            ));
            cursor += height;
            trailing = 0;
            kids[i] = rest;
            i--;
            continue;
          } else {
            _exclusions.length = mark;
            // Below them, if the region goes on that far.
            final skip = until - y;
            if (cursor + skip >= room - 1e-6) {
              return split(kids.sublist(i), from: i);
            }
            children.add((cursor, _PlacedSpace(skip)));
            cursor += skip;
            trailing = 0;
            i--;
            continue;
          }
        }
      }
      if (!placed) {
        fit = _place(child, inner, room - cursor, atTop: childAtTop);
      }
      // (One taller than a region starts the next region in the flow
      // instead, going on as it must: waiting at its edge, it would be
      // cut where the region ends.)
      if (fit.placed == null &&
          child.style.floating &&
          !childAtTop &&
          _floats(child) &&
          _measure(child, inner) <= _regionHeight + 1e-6) {
        _exclusions.length = mark;
        floated.add(child);
        _floatsWaiting++;
        continue;
      }
      // A box floating to the top or the bottom that doesn't fit whole
      // where the text reaches it (but would in a region of its own): for
      // the next region, whole, not cut where the room runs out. (One that
      // floats only when it doesn't fit, `next`, is set where it is.)
      if (fit.placed != null &&
          fit.rest != null &&
          child.style.floating &&
          child.style.float != FloatPlacement.next &&
          !childAtTop &&
          _floats(child) &&
          _measure(child, inner) <= _regionHeight + 1e-6) {
        _exclusions.length = mark;
        floated.add(child);
        _floatsWaiting++;
        continue;
      }
      if (fit.placed == null) {
        _exclusions.length = mark;
        return split(kids.sublist(i), from: i);
      }
      carried.addAll(fit.carried);
      floated.addAll(fit.floated);
      for (final (pin, y, height) in fit.pinned) {
        pinned.add((pin, top + cursor + y, height));
      }
      // A floating box that fits: for the top or bottom of the region.
      if (child.style.float case final float?
          when float != FloatPlacement.next &&
              fit.rest == null &&
              !childAtTop &&
              _floats(child) &&
              (child is BlockBox || child is CustomBox)) {
        pinned.add((child, top + cursor, fit.height));
      }
      if (fit.rest == null &&
          fit.hit == null &&
          child.style.keepWithNext &&
          i + 1 < kids.length &&
          !childAtTop) {
        final next = _minHeight(kids[i + 1], inner);
        if (cursor + fit.height + next > room + 1e-6) {
          _exclusions.length = mark;
          carried.removeRange(
            carried.length - fit.carried.length,
            carried.length,
          );
          return split(kids.sublist(i), from: i);
        }
      }
      children.add((cursor, fit.placed!));
      cursor += fit.height;
      // The space below what was just placed (a spacer, a box's margin).
      trailing = switch (child) {
        SpacerBox() => fit.height,
        _ when fit.rest == null => math.min(
          child.style.margin.bottom,
          fit.height,
        ),
        _ => 0.0,
      };
      if (fit.rest != null || fit.hit != null) {
        return split(
          [?fit.rest, ...kids.sublist(i + 1)],
          hit: fit.hit,
          from: fit.rest != null ? i : i + 1,
          partial: fit.rest != null,
        );
      }
    }
    // A block with a repeated head whose block floating to a side goes on
    // in the next region: the head goes on there too, beside it.
    if (carried.isNotEmpty && box.repeatedHead > 0 && _excluding) {
      return split(const [], from: box.children.length, headOnly: true);
    }
    // (At least its least height, unbroken.)
    if (!continued && cursor < style.minHeight) {
      cursor = room.isFinite
          ? math.max(cursor, math.min(style.minHeight, room))
          : style.minHeight;
    }
    // Its margin below no more than the room left (a region's end takes
    // what doesn't fit of it).
    final marginBottom = math.min<double>(
      style.margin.bottom,
      // ([room] has the bottom edge's room taken out when [reserved].)
      math.max<double>(0, room + (reserved ? bottom : 0) - cursor - bottom),
    );
    // Content run past the room it was given with its bottom edge's
    // room reserved (a text box's last line may run its gap below past
    // it): with [BoxStyle.splitToRegionEnd], the region's end cuts the
    // bottom edge off, the block reaching that end.
    final cut =
        reserved && style.splitToRegionEnd && room.isFinite && cursor > room;
    final placed = _PlacedBlock(
      style,
      width,
      cut ? top + room + bottom : top + cursor + bottom + marginBottom,
      children,
      top: atTop || continued ? 0 : style.margin.top,
      openTop: continued,
      openBottom: false,
      marks: continued ? const {} : style.marks,
      anchor: continued ? null : style.anchor,
      marginBottom: cut ? 0 : marginBottom,
    );
    return _Fit(
      placed,
      placed.height,
      null,
      floated: floated,
      pinned: pinned,
      carried: carried,
    );
  }

  /// The floating boxes set at the top or bottom of a region (their place
  /// in the flow is skipped).
  final Set<LayoutBox> _floatsSet = Set.identity();

  /// [box] set at the [top] or bottom of a region: not floating, its
  /// clearance ([BoxStyle.floatClearance]) on the content's side.
  static List<LayoutBox> _cleared(LayoutBox box, {required bool top}) {
    final clearance = box.style.floatClearance;
    if (clearance <= 0) return [_unfloated(box)];
    return top
        ? [_unfloated(box), SpacerBox(clearance)]
        : [SpacerBox(clearance), _unfloated(box)];
  }

  /// [box] (a floating block or custom box) as it is set at the top or
  /// bottom of a region: not floating.
  static LayoutBox _unfloated(LayoutBox box) => switch (box) {
    BlockBox(:final children, :final style) => BlockBox(
      children,
      style: style._unfloated,
    ),
    CustomBox(:final content, :final style) => CustomBox(
      content,
      style: style._unfloated,
    ),
    _ => box,
  };

  /// How many floating boxes wait for the next region in the placing
  /// under way (for float barriers).
  int _floatsWaiting = 0;

  /// The floating boxes set at a region's edge that the last placing of
  /// the content came to (passed over in the flow).
  final Set<LayoutBox> _floatsReached = Set.identity();

  /// The floating boxes that wait for the next region: the text before
  /// them goes on there.
  final Set<LayoutBox> _floatsNotHere = Set.identity();

  /// How deep the placing is in columns or tables, where boxes don't
  /// float.
  int _floatDepth = 0;

  /// Whether [child] may float here: at the top level, or out of columns
  /// when it spans them ([BoxStyle.floatSpan]).
  bool _floats(LayoutBox child) =>
      _floatDepth == 0 ||
      (child.style.floatSpan && _floatDepth == _columnsDepth);

  /// How many of the levels [_floatDepth] counts are columns.
  int _columnsDepth = 0;

  /// [place] with boxes not floating.
  _Fit _withoutFloats(_Fit Function() place) {
    _floatDepth++;
    try {
      return _withoutExclusions(place);
    } finally {
      _floatDepth--;
    }
  }

  // Blocks floating to a side ([BoxStyle.side]).

  /// Whether the blocks being placed go around blocks floating to a side
  /// (in a region's flow, not while measuring or in a framed block).
  bool _excluding = false;

  /// The blocks floating to a side in the region being filled.
  /// [child] set beside blocks floating to a side with outlines
  /// ([BoxStyle.sideShape]), line by line in the room they leave between
  /// [left] and [right] from [y] down, at most [room] tall, when it runs
  /// around them with [ShapedContent]: the piece, its height and the rest
  /// (null when it all fits).
  (_Placed, double, LayoutBox?)? _aroundShapes(
    LayoutBox child,
    double left,
    double right,
    double y,
    double room,
  ) {
    if (child is ParagraphBox) {
      return _paragraphAroundShapes(child, left, right, y, room);
    }
    if (child is! CustomBox ||
        !child.style.runsAround ||
        child.style.floating ||
        child.style.side != null) {
      return null;
    }
    final content = child.content;
    if (content is! ShapedContent) return null;
    final beside = [
      for (final other in _exclusions)
        if (other.top <= y + 1e-6 && other.bottom > y + 1e-6) other,
    ];
    if (!beside.any((other) => other.shape != null)) return null;
    final style = child.style;
    final margin = style.margin;
    final top = child._continued ? 0.0 : margin.top;
    final contentTop = y + top;
    final from = left + margin.left;
    final to = right - margin.right;
    (double, double) insets(double lineTop, double lineBottom) {
      var inLeft = 0.0;
      var inRight = 0.0;
      for (final other in beside) {
        final covered = other.covered(
          contentTop + lineTop,
          contentTop + lineBottom,
        );
        if (covered == null) continue;
        if (other.side == FloatSide.right) {
          inRight = math.max(inRight, to - (covered.$1 - other.gap));
        } else {
          inLeft = math.max(inLeft, covered.$2 + other.gap - from);
        }
      }
      return (math.max(0, inLeft), math.max(0, inRight));
    }

    final deepest = beside.map((other) => other.bottom).reduce(math.max);
    final placement = content.placeAround(
      to - from,
      math.min(deepest - contentTop, room - top),
      atTop: false,
      insets: insets,
    );
    if (placement == null) return null;
    final rest = placement.rest;
    final height =
        top +
        placement.height +
        (rest == null
            ? math.min(
                margin.bottom,
                math.max(0.0, room - top - placement.height),
              )
            : 0);
    return (
      _PlacedCustom(
        placement,
        margin.left,
        top,
        height,
        child._continued ? null : style.anchor,
        child._continued ? const {} : style.marks,
        width: to - from,
        decoration: style.decoration,
        first: !child._continued,
        last: rest == null,
        tag: style.tag,
      ),
      height,
      rest == null ? null : CustomBox._rest(rest, style),
    );
  }

  /// [_aroundShapes] for a paragraph: its lines, a step apart (its second
  /// line's height), each in the room the outlines beside it leave, the
  /// paragraph broken in those widths; what doesn't fit beside them goes
  /// on below, broken again.
  (_Placed, double, LayoutBox?)? _paragraphAroundShapes(
    ParagraphBox child,
    double left,
    double right,
    double y,
    double room,
  ) {
    final style = child.style;
    if (!style.runsAround || style.floating || style.side != null) {
      return null;
    }
    final beside = [
      for (final other in _exclusions)
        if (other.top <= y + 1e-6 && other.bottom > y + 1e-6) other,
    ];
    if (!beside.any((other) => other.shape != null)) return null;
    final margin = style.margin;
    final from = left + margin.left;
    final to = right - margin.right;
    final width = to - from;
    final source = child._source ?? child;
    final breaker = source.lineBreaker ?? layout.lineBreaker;
    if (breaker is! ItemLineBreaker) return null;
    final box = _reflowed(_reflowedAt(child, width), width);
    if (box == null) return null;
    final first = !box._continuation;
    final top = _topOf(box, margin);
    final contentTop = y + top;
    // (The step and the space above the first line's text, as the lines
    // are set across the width.)
    final plain = _linesOf(box, width);
    if (plain.isEmpty) return null;
    final pitch = (plain.length > 1 ? plain[1] : plain[0]).height;
    final gap = plain[0].baseline - plain[0].ascent;
    (double, double) insets(int line) {
      final lineTop = gap + line * pitch;
      final lineBottom = lineTop + pitch;
      var inLeft = 0.0;
      var inRight = 0.0;
      for (final other in beside) {
        final covered = other.covered(
          contentTop + lineTop,
          contentTop + lineBottom,
        );
        if (covered == null) continue;
        if (other.side == FloatSide.right) {
          inRight = math.max(inRight, to - (covered.$1 - other.gap));
        } else {
          inLeft = math.max(inLeft, covered.$2 + other.gap - from);
        }
      }
      return (math.max(0, inLeft), math.max(0, inRight));
    }

    final deepest = beside.map((other) => other.bottom).reduce(math.max);
    final available = math.min(deepest - contentTop, room - top);
    final count = available.isFinite ? (available / pitch).ceil() + 1 : 0;
    final bands = [for (var i = 0; i < count; i++) insets(i)];
    final paragraph = _resolve(box.paragraph);
    final items = box._items!;
    final (:lines, :breaks) = breaker.breakItemLines(
      paragraph,
      items,
      (line) => line < count ? width - bands[line].$1 - bands[line].$2 : width,
      offsets: (line) => line < count ? bands[line].$1 : 0,
    );
    final below = [
      for (final line in lines)
        math.max<double>(0, line.height - line.baseline - line.descent.abs()),
    ];
    final fit = layout.pageBreaker.linesThatFit(
      [for (final line in lines) line.height],
      available,
      orphans: box.orphans,
      widows: box.widows,
      atTop: false,
      below: below,
    );
    if (fit == 0) return null;
    final placed = lines.sublist(0, fit);
    var linesHeight = placed.fold<double>(0, (sum, line) => sum + line.height);
    final done = fit >= lines.length;
    if (!done && linesHeight > available + 1e-6) linesHeight -= below[fit - 1];
    final height =
        top +
        linesHeight +
        (done
            ? math.min(margin.bottom, math.max(0.0, room - top - linesHeight))
            : 0);
    final piece = _PlacedLines(
      placed,
      margin.left,
      top,
      height,
      first ? style.anchor : null,
      first ? style.marks : const {},
      style.tag,
      first: first,
    );
    return (
      switch (style.structure) {
        final element? => _PlacedTagged(element, piece),
        null => piece,
      },
      height,
      done
          ? null
          : ParagraphBox._reflowed(
              box,
              items.sublist(breaks[fit - 1] + 1),
              after: fit,
            ),
    );
  }

  /// The space above [box] where it starts: its margin, unless it goes on
  /// from lines set before.
  static double _topOf(ParagraphBox box, EdgeInsets margin) =>
      box._from > 0 || box._continuation ? 0 : margin.top;

  /// [child]'s first lines at [width] in the [height] beside blocks
  /// floating to a side, when it runs around them ([BoxStyle.runsAround])
  /// and some, not all, of it fits there: the piece, its height and the
  /// rest.
  (_Placed, double, LayoutBox)? _runaround(
    LayoutBox child,
    double width,
    double height,
  ) {
    if ((child is! CustomBox && child is! ParagraphBox) ||
        !child.style.runsAround ||
        child.style.floating ||
        child.style.side != null ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    final fit = _place(child, width, height, atTop: false);
    return switch ((fit.placed, fit.rest)) {
      (final piece?, final rest?) => (piece, fit.height, rest),
      _ => null,
    };
  }

  List<_Exclusion> _exclusions = [];

  /// The blocks moved to the next region to keep their repeated head
  /// whole, each moved once.
  final Set<BlockBox> _headsMoved = Set.identity();

  /// Those carried over from the region before, set at its top.
  List<_Exclusion> _seedExclusions = [];

  /// The width of the region being filled.
  double _regionWidth = 0;

  /// Where the box being placed starts: its top from the region's top,
  /// its edges from the region's.
  double _y = 0;

  double _left = 0;

  double _right = 0;

  /// Whether the region being filled is a column of a set: a block
  /// floating to a side there floats only when it fits in it whole.
  bool _inColumn = false;

  /// How far below the region's top [_y]'s origin is (a column's top: a
  /// column set resets [_y] for blocks floating to a side in it).
  double _yShift = 0;

  /// How far content whose first baseline is [baseline] below its top,
  /// which is [top] below [_y]'s origin, moves down to the baseline grid.
  double _gridShift(double top, double? baseline) {
    final line = _gridLine;
    _gridLine = null;
    final grid = _onGrid ? layout.baselineGrid : null;
    if (grid == null || baseline == null) return 0;
    final at = _yShift + top + baseline;
    // (The region's first line starts its grid, when it does.)
    final origin = grid.fromFirstLine ? _gridOrigin ??= at : grid.offset;
    // (Content at the region's top, below the grid's first line but above
    // the next, up to the first.)
    if (grid.raiseFirst &&
        line == null &&
        _yShift + top <= 1e-6 &&
        at > origin &&
        at - origin < grid.step) {
      return origin - at;
    }
    final shift = grid._shift(at, origin);
    // (A box that goes on a line of the grid, down to it.)
    if (line != null && line > 0) {
      return math.max(shift, origin + (line - 1) * grid.step - at);
    }
    return shift;
  }

  /// Whether [box] is the rest of one split by a break.
  static bool _isContinued(LayoutBox box) => switch (box) {
    BlockBox(:final _continued) || ColumnsBox(:final _continued) => _continued,
    ParagraphBox(:final _from, :final _continuation) =>
      _from > 0 || _continuation,
    _ => false,
  };

  /// The grid line the next line placed goes on, at the least
  /// ([BoxStyle.gridLine] of the box it starts).
  int? _gridLine;

  /// Where the region's grid starts, for one from its first line
  /// ([BaselineGrid.fromFirstLine]): set by the first line placed.
  double? _gridOrigin;

  /// Whether what is placed is a region's text, which keeps to the
  /// baseline grid (not notes, nor blocks floating out of it).
  bool _onGrid = false;

  /// How far below the top of the page's region the last region's content
  /// was placed (see [_placeRegion]).
  double _below = 0;

  /// [place] in a column [width] wide: a region of its own for blocks
  /// floating to a side (the column's, from its top).
  _Fit _column(double width, double origin, _Fit Function() place) {
    final saved = (_exclusions, _regionWidth, _y, _left, _right, _excluding);
    final savedInColumn = _inColumn;
    final savedShift = _yShift;
    _yShift += origin;
    _exclusions = [];
    _regionWidth = width;
    _y = _left = _right = 0;
    _excluding = true;
    _inColumn = true;
    try {
      return place();
    } finally {
      _exclusions = saved.$1;
      _regionWidth = saved.$2;
      _y = saved.$3;
      _left = saved.$4;
      _right = saved.$5;
      _excluding = saved.$6;
      _inColumn = savedInColumn;
      _yShift = savedShift;
    }
  }

  /// [place] with no block floating to a side.
  _Fit _withoutExclusions(_Fit Function() place) {
    final saved = _excluding;
    _excluding = false;
    try {
      return place();
    } finally {
      _excluding = saved;
    }
  }

  /// [place] off the baseline grid (a block floating to a side).
  _Fit _offGrid(_Fit Function() place) {
    final saved = _onGrid;
    _onGrid = false;
    try {
      return place();
    } finally {
      _onGrid = saved;
    }
  }

  /// [content] placed in a region [width] wide and [room] high, beside
  /// the blocks floating to a side carried there, [below] the top of the
  /// page's region (under floating boxes at its top: the baseline grid is
  /// the page's).
  _Fit _placeRegion(
    LayoutBox content,
    double width,
    double room, {
    double? below,
  }) {
    // (Placed again, for notes say: as far down as the last time.)
    _below = below ??= _below;
    _exclusions = [..._seedExclusions];
    _regionWidth = width;
    _y = _left = _right = 0;
    _yShift = below;
    _gridOrigin = null;
    _gridLine = null;
    _excluding = true;
    _onGrid = true;
    try {
      return _place(content, width, room, atTop: true);
    } finally {
      _excluding = false;
      _onGrid = false;
    }
  }

  /// Whether [box] is a block whose children go around blocks floating to
  /// a side each on its own (one without a frame or a keep).
  static bool _transparent(LayoutBox box) =>
      box is BlockBox &&
      box.style.padding == EdgeInsets.zero &&
      box.style.border == Border.none &&
      box.style.background == null &&
      box.style.decoration == null &&
      !box.style.keepTogether &&
      box.style.side == null;

  /// [box] (a block floating to a side) not floating.
  static BlockBox _unsided(LayoutBox box) => switch (box) {
    BlockBox(:final children, :final style) => BlockBox(
      children,
      style: style._unsided,
    ),
    _ => BlockBox([box]),
  };

  /// [rest] (of a block floating to a side as [style] says) floating
  /// again, for the next region.
  static BlockBox _sided(LayoutBox rest, BoxStyle style) => BlockBox(
    [rest],
    style: BoxStyle(
      side: style.side,
      sideWidth: style.sideWidth,
      sideGap: style.sideGap,
    ),
  );

  /// The height of the region being filled (for keep rules).
  double _regionHeight = double.infinity;
}
