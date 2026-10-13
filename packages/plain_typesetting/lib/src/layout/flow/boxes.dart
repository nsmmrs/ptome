part of '../flow.dart';

// The box tree: styles, the boxes, custom content, tables.

/// Distances on the four sides of a box.
@immutable
final class EdgeInsets {
  /// The given sides (0 elsewhere).
  const new({this.top = 0, this.right = 0, this.bottom = 0, this.left = 0});

  /// [value] on every side.
  const new all(double value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  /// [vertical] above and below, [horizontal] left and right.
  const new symmetric({double vertical = 0, double horizontal = 0})
    : top = vertical,
      bottom = vertical,
      left = horizontal,
      right = horizontal;

  /// No distance.
  static const EdgeInsets zero = EdgeInsets();

  /// The top distance.
  final double top;

  /// The right distance.
  final double right;

  /// The bottom distance.
  final double bottom;

  /// The left distance.
  final double left;

  /// Left plus right.
  double get horizontal => left + right;

  /// Top plus bottom.
  double get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// A box's border: its width on each side, one color, and a corner
/// radius (drawn when the four widths are the same).
@immutable
final class Border {
  /// A border of [widths] in [color].
  const new({
    this.widths = EdgeInsets.zero,
    this.color = const GrayColor(0),
    this.radius = 0,
  });

  /// The width on each side.
  final EdgeInsets widths;

  /// The color.
  final Color color;

  /// The corner radius.
  final double radius;

  /// No border.
  static const Border none = Border();
}

/// Paints extra decoration over a block's background and border, before
/// its content: [rect] is the part of the block (inside its margins) on
/// [page]; [first] and [last] tell whether it is where the block starts
/// and ends (a block split across pages has a piece on each).
typedef BoxDecoration = void Function(
  LayoutPage page,
  Rect rect, {
  required bool first,
  required bool last,
});

/// How a box is spaced, decorated and kept with others.
@immutable
final class BoxStyle {
  /// A style.
  const new({
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.border = Border.none,
    this.background,
    this.keepTogether = false,
    this.keepWithNext = false,
    this.anchor,
    this.marks = const {},
    this.decoration,
    this.tag,
    this.float,
    this.floatBarrier = false,
    this.verticalAlign,
    this.cloneEdges = false,
    this.splitToRegionEnd = false,
    this.floatClearance = 0,
    this.floatSpan = false,
    this.side,
    this.sideWidth = 0,
    this.sideGap = 0,
    this.sideShape,
    this.runsAround = false,
    this.numberLines = false,
    this.gridLine,
    this.minHeight = 0,
    this.structure,
  });

  /// The space outside the border.
  final EdgeInsets margin;

  /// The space between the border and the content.
  final EdgeInsets padding;

  /// The border.
  final Border border;

  /// The fill inside the border.
  final Color? background;

  /// Whether the box moves to the next region rather than split (when it
  /// fits in a whole region).
  final bool keepTogether;

  /// Whether the box stays in the region where the next box starts.
  final bool keepWithNext;

  /// With a [BaselineGrid], the line of the region's grid (from 1) the
  /// box's first baseline goes on, or the first one after where it would
  /// go when that is past it: a pleading's court title on line 8 of its
  /// first page, whatever is above it.
  final int? gridLine;

  /// What the box's content is in the document's logical structure, or
  /// null for none of its own (its content its parent's): painted on a
  /// [StructureCanvas], the box's content is that element's. A table's
  /// rows and cells are its `TR`s and `TH`s or `TD`s.
  final StructureElement? structure;

  /// The least height of a block's content (CSS's `min-height`): one that
  /// ends shorter, unbroken, is as tall (a paragraph shorter than its drop
  /// initial, as deep as the initial).
  final double minHeight;

  /// A name for the box's position (its top), for destinations.
  final String? anchor;

  /// A name the layout reports the pages the box is placed on by
  /// ([LayoutResult.tagPages]): the first and the last, when it breaks
  /// across pages.
  final String? tag;

  /// Running marks the box sets where it starts (a chapter title for the
  /// running header).
  final Map<String, String> marks;

  /// Extra decoration: of a block, painted over its background and
  /// border; of a custom box, painted under its content (in the box's
  /// width, without its margins).
  final BoxDecoration? decoration;

  /// Where the box floats (a figure), or null when it stays in the flow.
  /// A floating box that doesn't fit where it is (and isn't at the top of
  /// a region) goes to the top of the next region, the content after it
  /// filling the room; one that fits goes to the top or the bottom of its
  /// region ([FloatPlacement]), the content flowing around it. Blocks and
  /// custom boxes float, not inside columns, tables or framed blocks.
  final FloatPlacement? float;

  /// Whether the box floats.
  bool get floating => float != null;

  /// Whether floating boxes waiting for the next region keep the box
  /// from being placed before them (a section heading): it starts the
  /// next region after them.
  final bool floatBarrier;

  /// Where a block that starts a region, and fits in it whole, sits in
  /// the room there: at the top (as without), in the middle or at the
  /// bottom (a dedication alone on its page). Blocks only.
  final VerticalAlign? verticalAlign;

  /// Whether each piece of a block split across regions has the block's
  /// padding and border at its top and bottom (CSS's `box-decoration-break:
  /// clone`), rather than
  /// the first piece alone at its top and the last at its bottom.
  final bool cloneEdges;

  /// Whether the piece of a block split across regions that a region's end
  /// cuts off reaches that end (its background and border with it), as
  /// the bounding boxes of engines that draw a block after placing its
  /// content do, rather than ending under its last child.
  final bool splitToRegionEnd;

  /// The space between a floating box set at the top or bottom of a
  /// region and the content (below it at the top, above it at the
  /// bottom: LaTeX's `\textfloatsep`).
  final double floatClearance;

  /// Whether the floating box, in columns, leaves them for the top or
  /// bottom of the region across all of them (LaTeX's `figure*`, CSS's
  /// `column-span: all`): a map across a two-column page.
  final bool floatSpan;

  /// The side the block floats to, [sideWidth] wide, the blocks after it
  /// set beside it ([sideGap] from it) or, where one doesn't fit beside it
  /// whole, below it (CSS's `float` with blocks that avoid it, as a
  /// report's sidebar); null when it stays in the flow. Where it doesn't
  /// fit in its region, the rest goes on at the top of the next region,
  /// before anything else there, what is set there going around it too.
  /// Blocks only, not inside columns, tables or framed blocks.
  final FloatSide? side;

  /// The width of a block floating to a [side].
  final double sideWidth;

  /// The space between a block floating to a [side] and the blocks
  /// beside it.
  final double sideGap;

  /// Whether the box, a paragraph's [CustomBox] (whose content places
  /// its rest at any width, as text set again), runs around blocks
  /// floating to a [side] when it doesn't fit beside them whole: its
  /// first lines set beside them as far as they go, its rest at the full
  /// width below them. Otherwise it goes below them whole.
  final bool runsAround;

  /// The outline of a block floating to a [side], where a paragraph that
  /// [runsAround] it (with [ShapedContent]) is set line by line: an
  /// image's shape, say. Null: its box.
  final FloatShape? sideShape;

  /// Whether the lines of text in the box are numbered: the page's
  /// [PageInfo.lines] lists where they are, for a page template to set
  /// numbers beside them (line-numbered bills, critical editions).
  final bool numberLines;

  /// This style with [tag] ([BoxStyle.tag]).
  BoxStyle withTag(String? tag) => _copy(tag: (tag,));

  /// This style not floating to a side ([side]).
  BoxStyle get _unsided =>
      _copy(side: (null,), sideWidth: 0, sideGap: 0, sideShape: (null,));

  /// This style without floating.
  BoxStyle get _unfloated => _copy(float: (null,), floatSpan: false);

  /// This style with the room above the block as its top margin (where
  /// [verticalAlign] put it), kept together no more.
  BoxStyle _lowered(double room) => _copy(
    margin: EdgeInsets(
      top: room,
      right: margin.right,
      bottom: margin.bottom,
      left: margin.left,
    ),
    keepTogether: false,
    verticalAlign: (null,),
  );

  /// This style with the values given changed (the nullable ones in a
  /// record, so that null clears them).
  BoxStyle _copy({
    EdgeInsets? margin,
    bool? keepTogether,
    bool? floatSpan,
    double? sideWidth,
    double? sideGap,
    (String?,)? tag,
    (FloatPlacement?,)? float,
    (VerticalAlign?,)? verticalAlign,
    (FloatSide?,)? side,
    (FloatShape?,)? sideShape,
    (StructureElement?,)? structure,
  }) => BoxStyle(
    margin: margin ?? this.margin,
    padding: padding,
    border: border,
    background: background,
    keepTogether: keepTogether ?? this.keepTogether,
    keepWithNext: keepWithNext,
    anchor: anchor,
    marks: marks,
    decoration: decoration,
    tag: tag == null ? this.tag : tag.$1,
    float: float == null ? this.float : float.$1,
    floatBarrier: floatBarrier,
    verticalAlign: verticalAlign == null
        ? this.verticalAlign
        : verticalAlign.$1,
    cloneEdges: cloneEdges,
    splitToRegionEnd: splitToRegionEnd,
    floatClearance: floatClearance,
    floatSpan: floatSpan ?? this.floatSpan,
    side: side == null ? this.side : side.$1,
    sideWidth: sideWidth ?? this.sideWidth,
    sideGap: sideGap ?? this.sideGap,
    sideShape: sideShape == null ? this.sideShape : sideShape.$1,
    runsAround: runsAround,
    numberLines: numberLines,
    gridLine: gridLine,
    minHeight: minHeight,
    structure: structure == null ? this.structure : structure.$1,
  );

  /// This style with [structure] in place of its own.
  BoxStyle withStructure(StructureElement? structure) =>
      _copy(structure: (structure,));
}

/// The outline of a block floating to a side ([BoxStyle.sideShape]):
/// what it covers across each band [bandHeight] tall, from its top down,
/// as a range from its left edge; null for a band it leaves empty. Below
/// the last band it covers its whole width.
@immutable
final class FloatShape {
  /// An outline of [bands], each [bandHeight] tall.
  const new(this.bandHeight, this.bands);

  /// The height of each band.
  final double bandHeight;

  /// What each band covers, left to right from the block's left edge.
  final List<(double, double)?> bands;
}

/// The side a block floats to ([BoxStyle.side]).
enum FloatSide {
  /// The left.
  left,

  /// The right.
  right,
}

/// Where a floating box goes when it fits in its region.
enum FloatPlacement {
  /// Where it is: it floats only when it doesn't fit (to the top of the
  /// next region).
  next,

  /// To the top of its region.
  top,

  /// To the bottom of its region (above its notes).
  bottom,

  /// To the top or the bottom of its region, whichever it is nearer.
  auto,
}

/// How a box narrower than its region sits in it.
enum BoxAlign {
  /// At the left.
  left,

  /// Centered.
  center,

  /// At the right.
  right,
}

/// A box of the layout tree.
@immutable
sealed class LayoutBox {
  const new _(this.style);

  /// The box's style.
  final BoxStyle style;
}

/// A box holding other boxes, one below the other.
final class BlockBox extends LayoutBox {
  /// A block of [children], the first [repeatedHead] of them set again at
  /// the top of each later piece of it (a section's heading at the top of
  /// each page the section goes on to, as a table's header rows).
  const new(
    this.children, {
    BoxStyle style = const BoxStyle(),
    this.repeatedHead = 0,
  }) : _continued = false,
       _containsMargins = false,
       super._(style);

  const new _rest(
    this.children,
    BoxStyle style, {
    this.repeatedHead = 0,
    this._containsMargins = false,
  }) : _continued = true,
       super._(style);

  /// The content of a table cell, keeping its first child's margin above
  /// when it contains margins (as CSS's table cells contain their
  /// content's margins) rather than starting at the cell's edge.
  const new _cell(this.children, {required this._containsMargins})
    : repeatedHead = 0,
      _continued = false,
      super._(const BoxStyle());

  /// The children.
  final List<LayoutBox> children;

  /// How many of the first [children] each later piece of the block
  /// starts with again.
  final int repeatedHead;

  /// Whether this is the rest of a block split by a break (no top margin,
  /// border or padding).
  final bool _continued;

  /// Whether its first child keeps its margin above where the block
  /// starts at the top of a region.
  final bool _containsMargins;
}

/// A paragraph: lines broken from inline content. Its style's margins
/// apply; for padding, borders or a background, put it in a [BlockBox].
final class ParagraphBox extends LayoutBox {
  /// A box of [paragraph], keeping at least [orphans] lines before a
  /// break and [widows] after one.
  const new(
    this.paragraph, {
    BoxStyle style = const BoxStyle(),
    this.orphans = 2,
    this.widows = 2,
    this.lineBreaker,
  }) : _from = 0,
       _to = null,
       _source = null,
       _width = null,
       _items = null,
       _continuation = false,
       super._(style);

  /// The lines of [source] from [_from] on, broken at [_width] (null: at
  /// whatever width it is placed).
  new _rest(ParagraphBox source, this._from, [this._width])
    : paragraph = source.paragraph,
      orphans = source.orphans,
      widows = source.widows,
      lineBreaker = source.lineBreaker,
      _to = null,
      _source = source._source ?? source,
      _items = source._items,
      _continuation = source._continuation,
      super._(source.style);

  /// Lines [_from] to [_to] of [source] (a page planned to end after them).
  new _slice(ParagraphBox source, this._from, int this._to)
    : paragraph = source.paragraph,
      orphans = source.orphans,
      widows = source.widows,
      lineBreaker = source.lineBreaker,
      _source = source._source ?? source,
      _width = null,
      _items = source._items,
      _continuation = source._continuation,
      super._(source.style);

  /// The rest of [source], its [_items] after the lines set, broken again
  /// (where it goes on at another width: beside a block floating to a
  /// side, below it, in a column of another width).
  /// [after] lines set (those of them its [Paragraph.hangLines] set in
  /// counted off).
  ///
  /// With [first], all of [source], its items as they are.
  new _reflowed(
    ParagraphBox source,
    List<LineItem> this._items, {
    bool first = false,
    int after = 0,
  }) : paragraph = first
           ? source.paragraph
           : source.paragraph.copyWith(
               firstLineIndent: 0,
               hangLines: math.max(0, source.paragraph.hangLines - after),
             ),
       orphans = source.orphans,
       widows = source.widows,
       lineBreaker = source.lineBreaker,
       _from = 0,
       _to = null,
       _source = null,
       _width = null,
       _continuation = !first,
       super._(source.style);

  /// The paragraph.
  final Paragraph paragraph;

  /// The fewest lines before a break.
  final int orphans;

  /// The fewest lines after a break.
  final int widows;

  /// The line breaker, or null for the layout's.
  final LineBreaker? lineBreaker;

  /// The first line of this piece.
  final int _from;

  /// The line after this piece's last, or null for the paragraph's end.
  final int? _to;

  /// The paragraph this is the rest of.
  final ParagraphBox? _source;

  /// The width this rest's lines were broken at, when it may go on at
  /// another (then broken again).
  final double? _width;

  /// The items of the rest of a paragraph broken again, or null for its
  /// paragraph's own.
  final List<LineItem>? _items;

  /// Whether this goes on from lines set before (no margin above, anchor
  /// or marks of its own).
  final bool _continuation;
}

/// An image of a given size.
final class ImageBox extends LayoutBox {
  /// [image] (raster or SVG) at [width] by [height], aligned by [align];
  /// [shrinkToFit]
  /// scales it down when it is taller than a whole region.
  const new(
    this.image,
    this.width,
    this.height, {
    BoxStyle style = const BoxStyle(),
    this.align = BoxAlign.left,
    this.shrinkToFit = true,
  }) : super._(style);

  /// The image.
  final Graphic image;

  /// The width.
  final double width;

  /// The height.
  final double height;

  /// Its alignment.
  final BoxAlign align;

  /// Whether it shrinks to fit a region.
  final bool shrinkToFit;
}

/// Vertical space, dropped at the top of a region.
final class SpacerBox extends LayoutBox {
  /// [height] points of space.
  const new(this.height) : super._(const BoxStyle());

  /// The height.
  final double height;
}

/// A box of a fixed height, drawn by a callback (a rule, a custom
/// graphic).
final class DrawingBox extends LayoutBox {
  /// A box [height] tall (and [width] wide, or the region's width) that
  /// [draw] paints into its rectangle.
  const new(
    this.height,
    this.draw, {
    this.width,
    BoxStyle style = const BoxStyle(),
    this.align = BoxAlign.left,
  }) : super._(style);

  /// The height.
  final double height;

  /// The width, or null for the region's width.
  final double? width;

  /// Paints the box into its rectangle.
  final void Function(Canvas canvas, Rect rect) draw;

  /// Its alignment.
  final BoxAlign align;
}

/// Where a break goes.
enum BreakKind {
  /// To the next page.
  page,

  /// To the next column (or page, after the last column).
  column,
}

/// A side of a spread: recto pages are the odd-numbered ones (the
/// first page is a recto), verso pages the even-numbered ones.
enum PageSide {
  /// An odd-numbered page.
  recto,

  /// An even-numbered page.
  verso;

  /// The side of page [number] (1-based).
  static PageSide of(int number) => number.isOdd ? recto : verso;
}

/// A forced break.
final class BreakBox extends LayoutBox {
  /// A break to the next page, made from the template named [template]
  /// (the layout's choice when null); ignored at the top of a region
  /// unless [force]d (which leaves the region blank). With a [side], the
  /// content after the break starts on a page of that side, after a blank
  /// page when needed (and at the top of a page of the other side, that
  /// page stays blank).
  const new page({this.template, this.force = false, this.side})
    : kind = BreakKind.page,
      super._(const BoxStyle());

  /// A break to the next column, ignored at the top of a region unless
  /// [force]d.
  const new column({this.force = false})
    : kind = BreakKind.column,
      template = null,
      side = null,
      super._(const BoxStyle());

  /// The kind of break.
  final BreakKind kind;

  /// The template of the next page.
  final String? template;

  /// Whether the break is made even at the top of a region.
  final bool force;

  /// The side of the page the content after the break starts on.
  final PageSide? side;
}

/// A rule between the columns of a set that have content ([ColumnsBox.rule]),
/// down the taller of the two.
@immutable
final class ColumnRule {
  /// A rule [width] wide in [color].
  const new({this.width = 0.5, this.color = const GrayColor(0)});

  /// The rule's width.
  final double width;

  /// The rule's color.
  final Color color;
}

/// Boxes flowing through [count] columns, column by column, from where
/// the set starts to the bottom of the region (and on to the next); with
/// [balance], the columns of the region the set ends in as even as they
/// can be (so what follows the set, a heading across them say, comes
/// right under its shortest height).
final class ColumnsBox extends LayoutBox {
  /// [children] in [count] columns [gap] apart.
  const new(
    this.children, {
    this.count = 2,
    this.gap = 12,
    this.balance = false,
    this.rule,
    BoxStyle style = const BoxStyle(),
  }) : _continued = false,
       super._(style);

  const new _rest(
    this.children,
    this.count,
    this.gap,
    this.balance,
    this.rule,
    BoxStyle style,
  ) : _continued = true,
      super._(style);

  /// The children.
  final List<LayoutBox> children;

  /// The number of columns.
  final int count;

  /// The space between columns.
  final double gap;

  /// Whether the columns of the set's last region are balanced.
  final bool balance;

  /// The rule between columns, if any.
  final ColumnRule? rule;

  final bool _continued;
}

/// Content that lays itself out: the layout gives it the width and the
/// height left, and it places as much as fits. Callers implement it to
/// reproduce another engine's text boxes exactly, with the box tree
/// still deciding pagination around them.
abstract interface class CustomContent {
  /// As much of the content as fits in [available] height at [width]
  /// (`rest` holds what is left), or null to move all of it to the next
  /// region. With [atTop] (nothing above it in the region), something
  /// must be placed.
  CustomPlacement? place(double width, double available, {required bool atTop});

  /// The least height the content needs where it starts (to keep a box
  /// with it).
  double minHeight(double width);

  /// The narrowest and widest the content can usefully be (for automatic
  /// table columns).
  (double, double) intrinsicWidths();
}

/// Custom content made of lines laid out once per width (a paragraph a
/// caller sets itself): the layout asks how many of its lines fit, keeps
/// as many of them as the [PageBreaker] allows (its orphans and widows,
/// as for a [ParagraphBox]) and has the content place that many. The
/// content can lay its lines out once per width and answer every height
/// from them (the layout tries several heights to make room for notes or
/// to balance columns).
///
/// The layout still calls [place] where no line fits even at the top of
/// a region, or where the content has no lines: it decides what then
/// goes there.
abstract interface class LinedContent implements CustomContent {
  /// How many lines the content is set in at [width].
  int lineCount(double width);

  /// How many of the content's first lines at [width] fit in [available]
  /// height (none to all of them).
  int linesThatFit(double width, double available);

  /// The first [count] lines at [width] placed (`count` from 1 to all of
  /// them; `rest` holds what follows).
  CustomPlacement placeLines(double width, int count);

  /// The fewest lines before a break.
  int get orphans;

  /// The fewest lines after a break.
  int get widows;
}

/// Custom content whose lines can each take their own part of its width:
/// beside a block floating to a side with a [FloatShape], a paragraph
/// that [BoxStyle.runsAround] it is set line by line in the room the
/// outline leaves.
abstract interface class ShapedContent implements CustomContent {
  /// As much of the content as fits in [available] height at [width],
  /// each line set in what [insets] leaves of the width (the room taken
  /// at its left and at its right, for the line between `top` and
  /// `bottom`, down from the content's top); `rest` holds what is left,
  /// to be placed as plain [CustomContent]. Null to set none of it here.
  CustomPlacement? placeAround(
    double width,
    double available, {
    required bool atTop,
    required (double, double) Function(double top, double bottom) insets,
  });
}

/// Custom content that can be set one after another with other content
/// in one run (notes run in, [NoteStream.joined]).
abstract interface class JoinableContent implements CustomContent {
  /// This content and [following], in order, [separator] between each,
  /// as one; null when they don't join (content of another kind).
  CustomContent? joinedWith(
    List<CustomContent> following, {
    required String separator,
  });
}

/// Custom content set in lines that knows where its first baseline is:
/// on a [BaselineGrid] it starts where that falls on a line of the grid.
abstract interface class BaselineContent implements CustomContent {
  /// How far below its top the content's first baseline is at [width];
  /// null when it has no line of text.
  double? firstBaseline(double width);
}

/// A series of side notes in a column of its own
/// ([FlowLayout.sideNoteStreams]).
@immutable
final class SideNoteStream {
  /// The stream [name], set in [column].
  const new(this.name, this.column);

  /// The stream's name ([FlowLayout.sideNoteStreamOf]).
  final String name;

  /// The column its notes are set in on a page, from its number (1-based)
  /// and its template, or null for none there.
  final Rect? Function(int number, PageTemplate template) column;
}

/// A series of notes at the bottom of a region besides the main one
/// ([FlowLayout.noteStreams]): its notes under its [separator], in
/// [columns] [columnGap] apart, balanced.
@immutable
final class NoteStream {
  /// The stream [name].
  const new(
    this.name, {
    this.separator,
    this.columns = 1,
    this.columnGap = 12,
    this.runIn,
  });

  /// Its notes in a region as one box (run in: one paragraph, as a
  /// critical apparatus sets its entries), if they are; else each its own.
  /// [joined] runs in paragraphs and [JoinableContent].
  final LayoutBox Function(List<LayoutBox> notes)? runIn;

  /// A [runIn] that sets notes one after another in one paragraph,
  /// [separator] between them: notes that are all [ParagraphBox]es, or
  /// all [CustomBox]es of [JoinableContent] that join; others as they
  /// are.
  static LayoutBox Function(List<LayoutBox> notes) joined({
    String separator = '\u2003',
  }) => (notes) {
    if (notes.length < 2) return BlockBox(notes);
    if (notes.every((note) => note is ParagraphBox)) {
      final paragraphs = [for (final note in notes) note as ParagraphBox];
      final first = paragraphs.first;
      final style = first.paragraph.content
          .whereType<TextRun>()
          .firstOrNull
          ?.style;
      return ParagraphBox(
        Paragraph(
          [
            for (final (i, box) in paragraphs.indexed) ...[
              if (i > 0 && style != null) TextRun(separator, style),
              ...box.paragraph.content,
            ],
          ],
          align: first.paragraph.align,
          lineHeight: first.paragraph.lineHeight,
          firstLineIndent: first.paragraph.firstLineIndent,
          hyphenator: first.paragraph.hyphenator,
          breakLongWords: first.paragraph.breakLongWords,
          hyphenRepetition: first.paragraph.hyphenRepetition,
          riseInLineHeight: first.paragraph.riseInLineHeight,
        ),
        style: first.style,
        orphans: first.orphans,
        widows: first.widows,
      );
    }
    if (notes
        case [
          CustomBox(content: final JoinableContent first, :final style),
          ...final rest,
        ]
        when rest.every((note) => note is CustomBox)) {
      if (first.joinedWith([
            for (final note in rest) (note as CustomBox).content,
          ], separator: separator)
          case final joined?) {
        return CustomBox(joined, style: style);
      }
    }
    return BlockBox(notes);
  };

  /// The stream's name ([FlowLayout.noteStreamOf]).
  final String name;

  /// What is set above its notes, if anything.
  final LayoutBox? separator;

  /// The columns its notes are set in.
  final int columns;

  /// The space between the columns.
  final double columnGap;
}

/// Lines a region's text keeps its baselines to ([FlowLayout.baselineGrid]):
/// [step] apart, the first [offset] below the region's top (where a line
/// of text starting at the top has its baseline), the same in every
/// region of the page template, so lines on the two sides of a leaf back
/// each other (line matching).
@immutable
final class BaselineGrid {
  /// Lines [step] apart, the first [offset] down (or, [fromFirstLine],
  /// where each region's first line is).
  const new(
    this.step, {
    this.offset = 0,
    this.fromFirstLine = false,
    this.raiseFirst = false,
  });

  /// Whether content at a region's top whose first baseline falls between
  /// the grid's first line and the next goes up to the first, its ascent
  /// reaching above the region's top: the first baseline at [offset]
  /// whatever the face (a fixed first-baseline offset, as a US bill's
  /// first line is 88 pt down the page). Otherwise content only ever
  /// goes down to the grid.
  final bool raiseFirst;

  /// Whether each region's grid starts at its first line's baseline,
  /// wherever that is, rather than at [offset]: a US bill's page that
  /// opens with a section heading, set higher than text, has its grid
  /// higher too, and one line more.
  final bool fromFirstLine;

  /// The space between two lines of the grid (the text's line height).
  final double step;

  /// Where the first line is, below the region's top.
  final double offset;

  /// How far [baseline], down from the region's top, is above the next
  /// line of the grid (zero on one).
  double shift(double baseline) => _shift(baseline, offset);

  double _shift(double baseline, double origin) {
    if (step <= 0) return 0;
    final above = baseline - origin;
    final lines = above <= 1e-6 ? 0 : ((above - 1e-6) / step).ceil();
    return math.max(0, origin + lines * step - baseline);
  }
}

/// What placing custom content gave.
final class CustomPlacement {
  /// A piece [height] tall that [paint] draws with its top left at (x,
  /// top), with [anchors] at offsets from that corner; [rest] is what
  /// didn't fit.
  const new({
    required this.height,
    required this.paint,
    this.rest,
    this.anchors = const [],
    this.lines = const [],
  });

  /// The height of the piece.
  final double height;

  /// Paints the piece on `page` (through its canvas) at (`x`, `top`).
  final void Function(LayoutPage page, double x, double top) paint;

  /// What didn't fit, or null.
  final CustomContent? rest;

  /// Names and offsets (right and down from the top left) of positions in
  /// the piece.
  final List<(String, double, double)> anchors;

  /// Its lines of text, for line numbers ([BoxStyle.numberLines]): their
  /// baselines down from its top, their ends right of its left edge.
  final List<PieceLine> lines;
}

/// A line of text in a [CustomPlacement]: its [baseline] down from the
/// piece's top, from [left] to [right] of its left edge; [continues] when
/// it goes on with the line before (a wrapped verse line, which logical
/// line numbers count once).
@immutable
final class PieceLine {
  /// A line at [baseline], [left] to [right].
  const new(
    this.baseline, {
    required this.left,
    required this.right,
    this.continues = false,
  });

  /// The baseline, down from the piece's top.
  final double baseline;

  /// The line's left end, right of the piece's left edge.
  final double left;

  /// The line's right end.
  final double right;

  /// Whether it goes on with the line before.
  final bool continues;
}

/// A numbered line of text on a page ([PageInfo.lines]), in the page's
/// coordinates: its [baseline], from [left] to [right].
@immutable
final class TypesetLine {
  /// A line at [baseline], [left] to [right].
  const new(
    this.baseline, {
    required this.left,
    required this.right,
    this.continues = false,
  });

  /// The baseline's height on the page.
  final double baseline;

  /// The line's left end.
  final double left;

  /// The line's right end.
  final double right;

  /// Whether it goes on with the line before (not the start of a line of
  /// the source).
  final bool continues;
}

/// A box of content that lays itself out (see [CustomContent]); its
/// style's margins apply.
final class CustomBox extends LayoutBox {
  /// A box of [content].
  const new(this.content, {BoxStyle style = const BoxStyle()})
    : _continued = false,
      super._(style);

  const new _rest(this.content, BoxStyle style)
    : _continued = true,
      super._(style);

  /// The content.
  final CustomContent content;

  final bool _continued;
}

/// How a cell's content sits in a row taller than it.
enum VerticalAlign {
  /// At the top.
  top,

  /// In the middle.
  middle,

  /// At the bottom.
  bottom,
}

/// A table cell: boxes, spanning columns and rows.
@immutable
final class TableCell {
  /// A cell of [content].
  const new(
    this.content, {
    this.colSpan = 1,
    this.rowSpan = 1,
    this.padding = const EdgeInsets.all(4),
    this.background,
    this.border = Border.none,
    this.verticalAlign = VerticalAlign.top,
    this.verticalOffset,
    this.decoration,
  }) : _openTop = false,
       _source = null;

  new _rest(TableCell cell, this.content, this.rowSpan)
    : _source = cell._source ?? cell,
      colSpan = cell.colSpan,
      padding = cell.padding,
      background = cell.background,
      border = cell.border,
      verticalAlign = cell.verticalAlign,
      verticalOffset = cell.verticalOffset,
      decoration = cell.decoration,
      _openTop = true;

  /// The content.
  final List<LayoutBox> content;

  /// The columns the cell spans.
  final int colSpan;

  /// The rows the cell spans.
  final int rowSpan;

  /// The space between the cell's edges and its content.
  final EdgeInsets padding;

  /// The fill.
  final Color? background;

  /// The border, centered on the cell's edges.
  final Border border;

  /// Where the content sits.
  final VerticalAlign verticalAlign;

  /// How far below the top of the room inside the padding the content
  /// sits, given that room's height and the content's (in place of
  /// [verticalAlign]).
  final double Function(double room, double contentHeight)? verticalOffset;

  /// Paints the cell's border (in place of [border]), over the content,
  /// given the cell's rectangle and whether the piece is where the cell
  /// starts and ends.
  final BoxDecoration? decoration;

  /// Whether this is the rest of a cell split by a break.
  final bool _openTop;

  /// The cell this is the rest of.
  final TableCell? _source;
}

/// A table row.
@immutable
final class TableRow {
  /// A row of [cells] (left to right, skipping columns that cells from
  /// rows above span), at least [minHeight] tall.
  const new(this.cells, {this.minHeight = 0});

  /// The cells.
  final List<TableCell> cells;

  /// The least height.
  final double minHeight;
}

/// The width of a table column.
@immutable
sealed class ColumnWidth {
  const new _();

  /// [points] wide.
  const factory fixed(double points) = FixedColumnWidth;

  /// A share of the width the fixed and auto columns leave, by [weight].
  const factory fraction(double weight) = FractionColumnWidth;

  /// As wide as the content wants, within what is available.
  const factory auto() = AutoColumnWidth;

  /// The width [width] gives for the table's width.
  const factory computed(double Function(double tableWidth) width) =
      ComputedColumnWidth;
}

/// A column of a fixed width.
final class FixedColumnWidth extends ColumnWidth {
  /// [points] wide.
  const new(this.points) : super._();

  /// The width.
  final double points;
}

/// A column sharing what is left.
final class FractionColumnWidth extends ColumnWidth {
  /// A share by [weight].
  const new(this.weight) : super._();

  /// The weight.
  final double weight;
}

/// A column as wide as its content.
final class AutoColumnWidth extends ColumnWidth {
  /// An auto column.
  const new() : super._();
}

/// A column whose width depends on the table's (a fixed column once the
/// table's width is known).
final class ComputedColumnWidth extends ColumnWidth {
  /// A column [width] wide for the table's width.
  const new(this.width) : super._();

  /// The width for the table's width.
  final double Function(double tableWidth) width;
}

/// When a table's cell borders are painted.
enum TableBorders {
  /// After every cell's content, so no content covers a border.
  above,

  /// With each cell, before its content (as prawn-table paints them), so a
  /// cell's content may cover its borders.
  withCells,
}

/// A table: rows of cells in columns. Header rows repeat at the top of
/// each region the table continues in.
final class TableBox extends LayoutBox {
  /// A table of [rows] in [columns]; the first [headerRows] rows are the
  /// header. The table is [width] wide (the region's width when null; as
  /// narrow as its content allows with [shrinkToContent]).
  const new(
    this.rows, {
    required this.columns,
    this.headerRows = 0,
    this.width,
    this.shrinkToContent = false,
    this.borders = TableBorders.above,
    this.align = BoxAlign.left,
    this.stripes = const [],
    this.cellsContainMargins = false,
    BoxStyle style = const BoxStyle(),
  }) : _grid = null,
       _widths = null,
       super._(style);

  new _rest(TableBox table, this._grid, this._widths)
    : rows = table.rows,
      columns = table.columns,
      headerRows = table.headerRows,
      width = table.width,
      shrinkToContent = table.shrinkToContent,
      borders = table.borders,
      align = table.align,
      stripes = table.stripes,
      cellsContainMargins = table.cellsContainMargins,
      super._(table.style);

  /// The rows.
  final List<TableRow> rows;

  /// The columns' widths.
  final List<ColumnWidth> columns;

  /// The number of header rows.
  final int headerRows;

  /// The table's width.
  final double? width;

  /// Whether the table is as narrow as its content allows.
  final bool shrinkToContent;

  /// When the cells' borders are painted.
  final TableBorders borders;

  /// Its alignment when narrower than the region.
  final BoxAlign align;

  /// The backgrounds the body rows take in turn (cells without their own),
  /// counting from the first body row in each region.
  final List<Color?> stripes;

  /// Whether a cell's first block keeps its margin above, as CSS's table
  /// cells contain their content's margins, rather than starting at the
  /// cell's padding.
  final bool cellsContainMargins;

  /// The rows left to place (with their cells' columns), when this is the
  /// rest of a split table.
  final List<_GridRow>? _grid;

  /// The columns' widths, fixed by the first piece.
  final List<double>? _widths;
}

/// A row with each cell's column.
final class _GridRow {
  const new(this.cells, this.minHeight, {this.header = false});

  final List<(int, TableCell)> cells;
  final double minHeight;
  final bool header;
}
