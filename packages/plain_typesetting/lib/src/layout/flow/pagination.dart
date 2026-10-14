part of '../flow.dart';

// Pagination rules and templates, and the layout itself.

/// Decides where content breaks across regions.
abstract interface class PageBreaker {
  /// How many of the lines of [heights] go in [available] height (0 moves
  /// them all to the next region), keeping [orphans] lines before the
  /// break and [widows] after it; [atTop] when nothing is above them in
  /// the region (they can't move to a fresher one). [below]: the space
  /// under each line's text, which the region's last line may leave out.
  int linesThatFit(
    List<double> heights,
    double available, {
    required int orphans,
    required int widows,
    required bool atTop,
    List<double> below = const [],
  });

  /// How many lines of [total] go in a region where the first [fit] of
  /// them fit (0 moves them all to the next region), keeping [orphans]
  /// lines before the break and [widows] after it; [atTop] when nothing
  /// is above them in the region.
  int linesToKeep(
    int fit,
    int total, {
    required int orphans,
    required int widows,
    required bool atTop,
  });

  /// Whether a box kept together, [height] tall, moves to the next
  /// region rather than split, with [available] left of a region
  /// [regionHeight] tall.
  bool moveKeptBox(double height, double available, double regionHeight);
}

/// The usual rules: as many lines as fit, unless that leaves fewer than
/// the orphans before the break or the widows after it; kept boxes move
/// when they fit in a whole region.
final class DefaultPageBreaker implements PageBreaker {
  /// The default page breaker.
  const new();

  @override
  int linesThatFit(
    List<double> heights,
    double available, {
    required int orphans,
    required int widows,
    required bool atTop,
    List<double> below = const [],
  }) {
    var fit = 0;
    var used = 0.0;
    // (The region's last line may leave out the space under its text:
    // the space between lines goes at a break, as TeX's glue does.)
    while (fit < heights.length &&
        used + heights[fit] - (fit < below.length ? below[fit] : 0) <=
            available + 1e-6) {
      used += heights[fit];
      fit++;
    }
    return linesToKeep(
      fit,
      heights.length,
      orphans: orphans,
      widows: widows,
      atTop: atTop,
    );
  }

  @override
  int linesToKeep(
    int fit,
    int total, {
    required int orphans,
    required int widows,
    required bool atTop,
  }) {
    if (fit >= total) return total;
    // A line must go somewhere: at the top of a region, at least one.
    final least = atTop ? math.max(1, fit) : 0;
    if (fit < orphans) return least;
    if (total - fit < widows) {
      final kept = total - widows;
      return kept >= orphans ? kept : least;
    }
    return fit;
  }

  @override
  bool moveKeptBox(double height, double available, double regionHeight) =>
      height > available + 1e-6 && height <= regionHeight + 1e-6;
}

/// What a running header or footer knows about its page.
final class PageInfo {
  new _(
    this.number,
    this.count,
    this.label,
    this._marks,
    this.template,
    this._topMarks, {
    this.isEmpty = false,
    this.lines = const [],
  });

  /// The template of the page.
  final PageTemplate template;

  /// The page number (1-based).
  final int number;

  /// The number of pages.
  final int count;

  /// The page's label (its number as the layout writes it).
  final String label;

  final Map<String, String> _marks;

  /// Whether nothing was laid out on the page (a blank page before a
  /// recto or verso start, say).
  final bool isEmpty;

  /// The lines of text on the page whose boxes number them
  /// ([BoxStyle.numberLines]), in order: known once the page's content is
  /// painted (to its [PageTemplate.foreground]).
  final List<TypesetLine> lines;

  /// The value of the running mark [name] on this page: the first one set
  /// on the page, or else the last one set before it.
  String? mark(String name) => _marks[name];

  final Map<String, String> _topMarks;

  /// The value of the running mark [name] at the top of this page: the last
  /// one set before it (what a header set at the page's top sees: TeX's
  /// `\topmark`).
  String? topMark(String name) => _topMarks[name];
}

/// The pages content is laid out on.
@immutable
final class PageTemplate {
  /// Pages of [size] whose content area is inside [margins], in
  /// [columns] columns [columnGap] apart; [header] and [footer] give the
  /// boxes of the top and bottom margins (the header painted before the
  /// content, unless [runningOver]), [background] paints under the
  /// content and [foreground] over everything.
  const new(
    this.size, {
    this.margins = const EdgeInsets.all(72),
    this.columns = 1,
    this.columnGap = 12,
    this.header,
    this.footer,
    this.runningOver = false,
    this.background,
    this.foreground,
    this.bleed,
    this.writingMode = WritingMode.horizontal,
  });

  /// How the content area's lines run: across, or down in columns.
  /// Vertical, the content is laid out in a frame the content area turned
  /// a quarter turn (its lines across the frame, its blocks down it) and
  /// painted turned back ([frameToPage]); the header and footer stay
  /// across.
  final WritingMode writingMode;

  /// The page size.
  final Rect size;

  /// How far the sheet runs past [size] on every side, for content that
  /// is trimmed off in print: with a bleed (0 included), [size] is the
  /// `TrimBox` and the sheet (`MediaBox`, `BleedBox`) is [size] grown by
  /// it; without one (null), the page has no print boxes. Layout is on
  /// [size].
  final double? bleed;

  /// The margins around the content area.
  final EdgeInsets margins;

  /// The number of columns of the content area.
  final int columns;

  /// The space between columns.
  final double columnGap;

  /// The boxes of the top margin for a page.
  final List<LayoutBox> Function(PageInfo page)? header;

  /// The boxes of the bottom margin for a page.
  final List<LayoutBox> Function(PageInfo page)? footer;

  /// Whether the header is painted after the content, as the footer is
  /// (content reaching into the top margin then goes under it), rather
  /// than before it.
  final bool runningOver;

  /// Paints under a page's content.
  final void Function(Canvas canvas, PageInfo page)? background;

  /// Paints over a page's content and its header and footer.
  final void Function(Canvas canvas, PageInfo page)? foreground;

  /// The regions content flows through, in order: in the frame (its
  /// width the content area's height) when the [writingMode] is vertical.
  List<Rect> get regions {
    final vertical = writingMode != WritingMode.horizontal;
    final width = vertical
        ? size.height - margins.vertical
        : size.width - margins.horizontal;
    final height = vertical
        ? size.width - margins.horizontal
        : size.height - margins.vertical;
    final left = vertical ? 0.0 : size.left + margins.left;
    final bottom = vertical ? 0.0 : size.bottom + margins.bottom;
    final columnWidth = (width - columnGap * (columns - 1)) / columns;
    return [
      for (var i = 0; i < columns; i++)
        Rect(left + i * (columnWidth + columnGap), bottom, columnWidth, height),
    ];
  }

  /// Where a point of the frame vertical content is laid out in goes on
  /// the page: the frame turned a quarter turn clockwise, its top-left the
  /// content area's top-right, so that its lines run down the page and
  /// follow one another to the left ([WritingMode.verticalRightToLeft]);
  /// or, turned the same and mirrored across its lines, to the right
  /// ([WritingMode.verticalLeftToRight], each line mirrored back about
  /// its own middle as it is painted). The identity across.
  Matrix get frameToPage {
    final left = size.left + margins.left;
    final bottom = size.bottom + margins.bottom;
    final across = size.width - margins.horizontal;
    final down = size.height - margins.vertical;
    return switch (writingMode) {
      WritingMode.horizontal => const Matrix.identity(),
      WritingMode.verticalRightToLeft => Matrix(
        0,
        -1,
        1,
        0,
        left,
        bottom + down,
      ),
      WritingMode.verticalLeftToRight => Matrix(
        0,
        -1,
        -1,
        0,
        left + across,
        bottom + down,
      ),
    };
  }
}

/// How lines run on a page.
enum WritingMode {
  /// Across, left to right (or right to left), lines following down.
  horizontal,

  /// Down, lines following to the left: Japanese, Chinese
  /// (`vertical-rl`).
  verticalRightToLeft,

  /// Down, lines following to the right: Mongolian (`vertical-lr`).
  verticalLeftToRight,
}

/// Where an anchor ended up.
@immutable
final class AnchorPosition {
  /// [page] (0-based) at ([x], [y]).
  const new(this.page, this.x, this.y);

  /// The page index.
  final int page;

  /// The x coordinate.
  final double x;

  /// The y coordinate (the top of what is anchored).
  final double y;
}

/// Lays boxes out on pages.
final class FlowLayout {
  /// A layout of pages from [template] (or, by name, from [templates],
  /// whose `null` entry is the default), breaking lines with
  /// [lineBreaker] and pages with [pageBreaker]; [pageLabel] writes page
  /// numbers (for references and headers).
  new({
    PageTemplate? template,
    Map<String?, PageTemplate>? templates,
    this.pageBreaker = const DefaultPageBreaker(),
    this.lineBreaker = const FirstFitLineBreaker(),
    String Function(int number)? pageLabel,
    this.maxPasses = 5,
    this.startTemplate,
    this.keepTemplate = false,
    this.templateForPage,
    this.notes = const {},
    this.noteSeparator,
    this.noteStreams = const [],
    this.noteStreamOf = const {},
    this.notesMinText,
    this.notesLag,
    this.sideNotes = const {},
    this.sideColumn,
    this.sideNoteStreams = const [],
    this.sideNoteStreamOf = const {},
    this.sideNoteGap = 2,
    this.baselineGrid,
    this.pagination = Pagination.firstFit,
  }) : templates = {null: ?template, ...?templates},
       pageLabel = pageLabel ?? _decimal {
    if (this.templates[null] == null) {
      throw ArgumentError('a default page template is needed');
    }
  }

  /// The page templates by name (`null` is the default).
  final Map<String?, PageTemplate> templates;

  /// Decides where content breaks across regions.
  final PageBreaker pageBreaker;

  /// Breaks paragraphs into lines (unless a paragraph has its own).
  final LineBreaker lineBreaker;

  /// Writes a page number.
  final String Function(int number) pageLabel;

  /// The most layouts tried to resolve page references.
  final int maxPasses;

  /// The name of the first page's template (the default when null).
  final String? startTemplate;

  /// Whether a page break's template stays in effect for the pages after
  /// it (until another break names one), rather than for the next page
  /// alone. A break naming another template at the top of a page that's
  /// still empty then replaces that page.
  final bool keepTemplate;

  /// The template of each page, from the page number (1-based) and the
  /// template the content calls for (for margins that differ between recto
  /// and verso pages, say); the one the content calls for when null.
  final PageTemplate Function(PageTemplate template, int number)?
  templateForPage;

  /// Notes by the anchor that refers to them (footnotes): a note is set
  /// at the bottom of the region its anchor is placed in, the region's
  /// content making room for it; what doesn't fit there goes on at the
  /// bottom of the next region.
  final Map<String, LayoutBox> notes;

  /// What is set above the notes of a region (a short rule, say).
  final LayoutBox? noteSeparator;

  /// The series of [notes] besides the main one, set under it in this
  /// order, each under its own separator and in its own columns: a
  /// critical apparatus, a reference Bible's cross-references, a second
  /// series of footnotes.
  final List<NoteStream> noteStreams;

  /// The stream of each note in one ([NoteStream.name]), by its anchor;
  /// the others are the main series.
  final Map<String, String> noteStreamOf;

  /// The least height of text a region with notes holds when the notes
  /// of more text wouldn't all fit under it: so much text, its notes set
  /// under it as far as they go, the rest of them going on in the next
  /// regions (a study Bible's page, its notes far longer than its text).
  /// Null: a quarter of the region, and when even that much text's notes
  /// don't fit, the text fills the region, its notes going on after it.
  final double? notesMinText;

  /// How many regions after the one its reference is in a note may start
  /// in, at most: when one has waited so long, the text of the region
  /// stops at [notesMinText] (none, without it) to make room for it. Null
  /// for no limit.
  final int? notesLag;

  /// Notes set beside the text by the anchor that refers to them (a
  /// reference Bible's cross-references in its center column): each in
  /// the page's [sideColumn], in the order their anchors are read, each
  /// level with its anchor (or under the note before it, [sideNoteGap]
  /// apart), above the page's [notes]; what doesn't fit goes on at the top
  /// of the next page's (and is left out after the last page). They take
  /// no room from the text.
  final Map<String, LayoutBox> sideNotes;

  /// The column [sideNotes] are set in on a page, from its number
  /// (1-based) and its template, or null for none there.
  final Rect? Function(int number, PageTemplate template)? sideColumn;

  /// Series of [sideNotes] each in a column of its own (a Talmud page's
  /// commentaries around its text, a critical edition's marginal
  /// apparatus), set as the main series is in [sideColumn].
  final List<SideNoteStream> sideNoteStreams;

  /// The stream of each side note in one ([SideNoteStream.name]), by its
  /// anchor; the others are the main series.
  final Map<String, String> sideNoteStreamOf;

  /// The space between two side notes.
  final double sideNoteGap;

  /// The grid the text's baselines keep to, if any: each paragraph (and
  /// [BaselineContent]) starts where its first baseline falls on a line
  /// of it, the space before it rounded up to that, so its lines, set a
  /// step apart, are on the grid too, the same on every page.
  final BaselineGrid? baselineGrid;

  /// How the pages' breaks are chosen: one page at a time, or together
  /// (see [Pagination.optimal]).
  final Pagination pagination;

  static String _decimal(int number) => '$number';

  /// [content] with the optimal plan's page breaks, when every page is
  /// one region of the same size and nothing goes to the foot of a page;
  /// else null.
  List<LayoutBox>? _optimal(List<LayoutBox> content) {
    if (notes.isNotEmpty) return null;
    final first = templates[startTemplate] ?? templates[null]!;
    // (The pages of the template the layout starts with; a break to
    // another template is content the plan doesn't model.)
    final pages = [
      for (var number = 1; number <= 2; number++)
        templateForPage?.call(first, number) ?? first,
    ];
    final regions = [for (final page in pages) page.regions];
    if (regions.any((r) => r.length != 1)) return null;
    final region = regions.first.single;
    if (regions.any(
      (r) =>
          (r.single.width - region.width).abs() > 1e-6 ||
          (r.single.height - region.height).abs() > 1e-6,
    )) {
      return null;
    }
    final pass = _Pass(this, const {}).._regionHeight = region.height;
    return pass._optimallyPaged(content, region.width, region.height);
  }

  /// The lines of the paragraphs without page references, by paragraph
  /// box and width: kept from one [layout] to the next (the boxes and
  /// breakers are immutable, so the lines are too).
  final Expando<Map<double, List<Line>>> _lines = Expando();

  /// The narrowest and widest lines of the paragraphs without page
  /// references (without their margins and indent).
  final Expando<(double, double)> _intrinsics = Expando();

  /// [content] laid out on pages.
  LayoutResult layout(
    List<LayoutBox> content, {
    LayoutResult? reuse,
    int unchangedBefore = 0,
    Set<int>? changedPages,
  }) {
    // (Pages chosen together: the content with the plan's page breaks,
    // laid out afresh.)
    final planned = pagination == Pagination.optimal ? _optimal(content) : null;
    final boxes = planned ?? content;
    final previous = planned == null ? reuse : null;
    var anchors = <String, AnchorPosition>{};
    // Laid out again after a change at or after [unchangedBefore]: the
    // pages before the last clean boundary before it are kept, and the
    // first pass goes on from there.
    _Boundary? resumeAt;
    if (previous != null && identical(previous._layout, this)) {
      anchors = previous.anchors;
      for (final boundary in previous._boundaries) {
        if (boundary.index > unchangedBefore) break;
        if (boundary.index <= boxes.length && !boundary.hasReferences) {
          resumeAt = boundary;
        }
      }
    }
    late _Pass pass;
    for (var i = 0; i < maxPasses; i++) {
      pass = _Pass(this, anchors);
      if (i == 0 && resumeAt != null) {
        pass.resume(boxes, previous!, resumeAt, changedPages);
      } else {
        pass.run(boxes);
      }
      final found = pass.anchors;
      final stable =
          found.length == anchors.length &&
          found.entries.every((e) => anchors[e.key]?.page == e.value.page);
      anchors = found;
      if (stable || !pass.hasReferences) break;
    }
    return LayoutResult._(
      this,
      pass.pages,
      anchors,
      pass.tagPages,
      pass.boundaries,
      pass.repeatedAnchors,
      pass.unsetSideNotes,
    );
  }
}

/// A point between two pages of a pass where nothing is pending (no
/// floating box, deferred note or carried piece) and the rest of the
/// content is the top-level boxes from [index] on: a pass may go on from
/// here as from the start.
final class _Boundary {
  const new({
    required this.index,
    required this.pages,
    required this.template,
    required this.notesSet,
    required this.floatsSet,
    required this.hasReferences,
  });

  /// The first top-level box after the boundary.
  final int index;

  /// The pages before it.
  final int pages;

  /// The template the next page takes.
  final String? template;

  /// The notes placed before it.
  final Set<String> notesSet;

  /// The floating boxes set at a region's edge before it.
  final Set<LayoutBox> floatsSet;

  /// Whether the content before it refers to pages.
  final bool hasReferences;

  /// Whether a pass at [other] goes on as one at this boundary does
  /// (neither referring to pages, whose numbers may have moved).
  bool sameAs(_Boundary other) =>
      index == other.index &&
      pages == other.pages &&
      template == other.template &&
      !hasReferences &&
      !other.hasReferences &&
      notesSet.length == other.notesSet.length &&
      notesSet.containsAll(other.notesSet) &&
      floatsSet.length == other.floatsSet.length &&
      floatsSet.containsAll(other.floatsSet);
}
