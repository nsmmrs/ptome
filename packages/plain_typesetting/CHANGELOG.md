# Changelog

## 0.1.0-dev (unreleased)

- A line with right-to-left text keeps the runs that carry only an
  anchor (a footnote's reference), which reordering lost, and reports
  its anchors in reading order (`Line.readingOrder`,
  `Line.fragmentsInReadingOrder`), so that notes come in the order their
  references are read.
- `ParagraphContent`: a paragraph as `CustomContent` (lined, with a
  baseline and intrinsic widths), for content a caller composes around a
  paragraph (a list item's marker, a table of contents entry's leader)
  and still has the layout place, split and run around floats. Its lines
  are broken once per width; what goes on after a break is its line items
  broken again where it goes on, its first line marked as going on with
  the line before unless the break was forced (logical line numbers);
  orphans and widows are kept; it needs its first `orphans` lines to
  start, or all of it when too short to split; a placement that breaks
  ends at its last line's text; `slant` shifts each line as a block.
- `TextRun.slotWidth` and `slotAlign`: text set whole in a fixed width,
  aligned there by its glyphs' advances (a hung heading number, a key's
  label padded on both sides); a slot of spaces is fixed space.
  `TextRun.artifact` draws a run as marked content whose actual text is
  empty (a listing's callouts, left out of copied text).
  `InlineDecoration.outset` extends a decoration above and below.
- `Paragraph.breakOpportunities`: `spacesAndHyphens` breaks only at
  spaces, hyphens and hard breaks (source code, which UAX #14 would break
  after a slash). `Paragraph.copyWith` takes `lineHeight` and
  `breakOpportunities`.
- A line's width leaves out the tracking after its last character (an
  ordered list's right-aligned numbers sat half a point off), and a word
  as wide as the line within rounding is no longer split.
- `BaselineGrid.raiseFirst`: content at a region's top whose first
  baseline falls below the grid's first line, but above the next, goes
  up to the first, its ascent reaching above the region's top: a fixed
  first-baseline offset, whatever the face.
- Right-to-left paragraphs: `Paragraph.rightToLeft` sets a paragraph's
  lines from the right, its indents there; each line's text is put in
  visual order by the Unicode Bidirectional Algorithm, its runs split
  where their levels change and right-to-left runs shaped as such (in a
  left-to-right paragraph too, where it has right-to-left text).
  `TextStyle.shapeBidi` shapes a line's text in visual order.
- Right-to-left text and complex shaping: `Font.shape` (and
  `TextStyle.shape`) take `rightToLeft`, and `OpenTypeShaper` shapes a
  right-to-left run, or Arabic or Hebrew text, with the font's layout
  tables in full: marks reordered by their modified combining classes,
  Arabic compositions, the joining forms (`isol`, `fina`, `medi`,
  `init`) from the Joining_Type, the GSUB features in OpenType's order
  for the script (`ccmp`, `locl`, `rlig`, `calt`, `liga`, `mset`...),
  then `kern`, `mark` and `mkmk`; the glyphs come in visual order, mirrored
  where the character has a mirror. `ShapedGlyph.positioned` gives a
  glyph's `xOffset` and `yOffset` (a mark on its base). Checked against
  HarfBuzz (harfbuzzjs) on Arabic and Hebrew with their vowels and points
  in four Arabic and three Hebrew fonts: the same glyphs, advances and
  offsets for 6,225 to 6,229 of the Qur'an's 6,236 verses.
- `Paragraph.alignLast` (CSS's `text-align-last`: a justified paragraph's
  last line and those before a hard break) and `Paragraph.protrusion`
  (character protrusion with microtype's default amounts,
  `rightProtrusion` and `leftProtrusion`: a line's last character hung
  past its end, its first before its start when justified, the breaker
  counting them); `ItemLineBreaker.breakItems` takes the protrusion
  callbacks. A hyphenated line ends in the soft hyphen where the font
  has it (text taken from the page joins the word up), and a word's
  pieces at its breaks are measured within the word (the word up to a
  piece's end less the word before it), the kerning and any ligature
  across a break counted, so they add up to the word as it is drawn
  whole.
- `LineHeight.cap`: lines from their cap heights to their baselines (CSS's
  `text-box-edge: cap alphabetic`), the leading between them; a
  paragraph ends at its last baseline. `Paragraph.justifyToWidest`:
  justified lines stretched to the widest line's natural width, not the
  measure. `Paragraph.copyWith`. A font's cap height, where it gives
  none, is its typographic ascender. A break after a compound's hyphen
  is a hyphenated one (TeX's `\exhyphenpenalty`, 50, flagged); a space
  before what no line starts with (a comma, a closing bracket, a slash)
  or after an opening bracket is no break (UAX #14's LB13 and LB14); a
  justified paragraph's last line set wider than its measure hangs its
  first character too; a paragraph's margin below takes no more than the
  room left in its region, as a custom box's; a paragraph with page
  references keeps its other settings when they are filled in.
- A `ParagraphBox` that `runsAround` a block floating to a side is set
  beside it (its first lines in the room left, the rest broken again
  below it, as a custom box's), and beside an outline line by line
  (`FloatShape`). The rest of a paragraph going on at another width (in
  a column of another width) is broken again from its words after the
  lines set; it was broken whole at the new width and its first lines
  skipped. `ItemLineBreaker.breakItemLines` (a paragraph's lines from
  given items, with the item each breaks at) and `buildLines(offsets:)`.
- `Paragraph.hangIndent` and `hangLines` (TeX's `\hangindent` with a
  negative `\hangafter`: the first lines set in, a drop initial's room
  beside them), `Paragraph.firstLineContent` (CSS's `::first-line`: the
  paragraph broken in its first line's style, that line kept, the rest
  broken again in its own) and `BoxStyle.minHeight` (CSS's `min-height`
  for a block's content).
- `InlineImage.bottom`, `lineAscent` and `lineDescent`: where an inline
  image sits from the baseline and how far it reaches for its line's
  height, where those aren't its own (a formula on its depth; an icon no
  taller than its text).
- `LineHeight.font(endDepth:)`: how far below its baseline a paragraph's
  last line ends (a heading's or a table cell's text ending at its
  descender), and `Paragraph.strut` (TeX's `\strut`: each line at least
  as tall as text in a style).
- A document's logical structure: `StructureElement` (a standard
  structure type, alternate text, language, attributes) on a box's
  `BoxStyle.structure`; painted on a `StructureCanvas`, a tagged box's
  content is its element's, a tagged table's rows and cells its `TR`s
  and `TH`s or `TD`s (a header row repeated on a later piece an
  artifact), and the page template's content (running heads, page
  numbers) and blocks' backgrounds and borders artifacts.
  `BoxStyle.withStructure`.
- `TextRun.anchorOnBaseline`: a run's anchor reported at its baseline
  rather than its text's top (where a label hung beside the line aligns).
- A paragraph's last line in a region fits when its text does, the space
  under it left out (interline space goes at a break, as TeX's glue). A
  block's repeated head is kept whole and with what follows it: a break
  inside it, or right after it with nothing of what follows placed, moves
  the block to the next region once, and where it doesn't fit there
  either the head isn't repeated (the rest of a block broken in its head
  repeated the wrong children). A justified paragraph's last line set
  wider than its measure is shrunk to it, not left overfull.
- `Paragraph.riseInLineHeight` (false: a superscript reaches into the
  space between lines, the pitch kept); `LineHeight.font(above:)`, how
  much of the space between lines goes above the text (a Prawn text
  box's half the leading and the line gap); a run with an anchor and no
  text places its anchor; a word wider than a line across several runs
  breaks as one in a single run does.
- Grapheme clusters kept whole: font fallback picks one font for a base
  and its combining marks (or an emoji sequence, a flag), and a word too
  wide for its line splits between clusters, never inside one (clusters
  as the line breaking classes tell them: CM, ZWJ, EM, RI pairs).
- A box floating to the top or the bottom that doesn't fit whole where
  the text reaches it goes whole to the next region, not cut where the
  room runs out (one for `next` is set where it is, as before), and one
  for the bottom with no room for it under the text there waits for the
  next region's bottom. The notes referred to in a floating box set at a
  region's top or bottom are set (they were left out). A box pinned to
  the bottom that the text no longer reaches once its notes shorten it
  waits for the next region, never set a page before its text; a
  floating box taller than a region starts the next region in the flow
  rather than waiting at its edge, where its overflow was dropped.
- `BoxStyle.gridLine`: with a baseline grid, a box starts on that line of
  the region's grid, or the next one when it is past it.
- `FlowLayout.notesMinText` and `notesLag`: notes in step with their
  text (the least text a region with notes holds; how many regions late
  a note may start, the text stopping where its notes would start
  later). The search for the most text whose notes fit no longer tries
  rooms smaller than the content's first piece (forced in at the top),
  and the least height a box needs where it starts counts a column
  set's first box in a column's width and a paragraph's rest from the
  line it goes on with.
- Note streams: the notes left over at the bottom of a region go on in
  the next in their own stream (under its separator, in its columns, run
  in with that region's notes when the stream runs its notes in), not
  ahead of all the streams.
- `FlowLayout.pagination` (`Pagination.optimal`): the breaks of the pages
  chosen together by dynamic programming over a galley of the content
  (paragraphs' lines within their widow and orphan limits, other blocks
  whole), given to the layout as page breaks; content the plan can't
  model is laid out first-fit.
- `KnuthPlassLineBreaker.breakItems(protrudeLeft:, protrudeRight:)`: each
  line chosen as the wider measure its ends hang into. `lastLineMin` and
  `runtDemerits`: a paragraph's last line short of the least only when
  no pass with more stretch finds another way.
- A float that spans columns (`BoxStyle.floatSpan`) on a page template
  with columns goes across the top of the next page, its columns under
  it (as LaTeX's `figure*`). A column set inside a column is one unit:
  in the next column when it doesn't fit whole (a balanced set inside a
  balanced one was chopped into pieces).
- `FlowLayout.sideNoteStreams` (`SideNoteStream`) and `sideNoteStreamOf`:
  side notes in columns of their own. `NoteStream.runIn` sets a stream's
  notes in a region as one box; `NoteStream.joined` runs in paragraphs
  and `JoinableContent`.
- `BaselineGrid.fromFirstLine`: each region's grid from its first line.
- Table cells are laid out once: the content a row measured is placed as
  it is where it fits whole.
- `KnuthPlassLineBreaker.expansion` (font expansion, counted as stretch
  and shrink of the line's letters; `buildLines` and the paragraph lines
  set it by horizontal scaling) and `maxHyphenRun` (the most hyphenated
  lines in a row, part of each break's state).
- `FlowLayout.noteStreams` (`NoteStream`) and `noteStreamOf`: series of
  notes at the bottom of a region under the main one, each under its own
  separator and in its own balanced columns. Balanced columns no longer
  try a height shorter than their first box.
- `BoxStyle.numberLines`: the lines of text in the box are listed, where
  they are, in the page's `PageInfo.lines` (`TypesetLine`) for its
  template's foreground to number; custom content reports its lines in
  `CustomPlacement.lines` (`PieceLine`).
- `FlowLayout.baselineGrid` (`BaselineGrid`): a region's paragraphs, and
  custom content that is `BaselineContent`, start where their first
  baseline falls on a line of the grid, in columns and under floats at
  the top of the page too (notes and blocks floating to a side keep
  their own places).
- A block floating to a side inside a `ColumnsBox` floats in its column:
  the column is a region of its own for it; one that doesn't fit in the
  room left starts the next column, and one taller than a column is set
  in the flow. `ColumnsBox.rule` (`ColumnRule`) draws a rule between
  columns that have content.
- `BoxStyle.sideShape` (`FloatShape`): a side float's outline, band by
  band; a paragraph that runs around it with `ShapedContent`
  (`placeAround`) is set line by line in the room the outline leaves.
- `BoxStyle.runsAround`: a paragraph's custom box that doesn't fit beside
  blocks floating to a side runs around them, its first lines beside
  them as far as they go, its rest set again at the full width below
  them (a runaround); without it, it goes below them whole.
- Paragraph and page layout (`Paragraph`, the line breakers, `FlowLayout`
  and its boxes), the math layout (`MathLayout`), geometry, colors, the
  text style and `Graphic` moved from plain_pdf with their history, and
  the shaping loop from plain_pdf's embedded fonts (`OpenTypeShaper`).
- Independent of PDF: layouts draw on the `Canvas` interface and render
  into a `LayoutDocument` of `LayoutPage`s, set text in `Font`s, and link
  to `LinkTarget`s, which a backend implements (plain_pdf). `render` gives
  back the backend's own page type.
- Renamed from plain_pdf's names: `PdfRect` to `Rect`, `PdfMatrix` to
  `Matrix`, `PdfColor` to `Color`, `PdfTextStyle` to `TextStyle`.
- `OpenTypeShaper` is a `Font` on its own, compared with HarfBuzz.
- `KnuthPlassLineBreaker` is the optimal breaker, with TeX's costs by
  default (tolerance: a badness of 200; 10000 demerits for two hyphenated
  lines in a row or adjacent lines far apart in fitness; 5000 for a
  hyphenated next-to-last line), an emergency-stretch pass
  (`emergencyStretch`), and ragged lines broken as TeX's `\rightskip`
  sets them (`raggedStretch`). Fills are counted apart, so lines after a
  forced break inside a paragraph stretch as they should.
  `demeritsOf` gives the demerits of any breaks, for checking. It
  replaces the breaker modeled on another engine's (ADR-0021).
- Side notes still waiting when the text ends go on pages of their own
  (margin only) instead of being dropped; `LayoutResult.unsetSideNotes`
  names any no page's side column has room for.
- A compound's hyphen repeated at the next line's start where the
  language's typography has it so (`Paragraph.hyphenRepetition`,
  `HyphenRepetition.forLanguage`): a `PenaltyItem`'s
  `carry` is the width the next line starts with, which every breaker
  counts.
- Column sets can balance their last region (`ColumnsBox(balance:)`), and
  a floating box in columns can span them (`BoxStyle.floatSpan`, as
  LaTeX's `figure*`): across the top or bottom of the region.
- Blocks floating to a side (`BoxStyle.side`, `sideWidth`, `sideGap`):
  the blocks after one are set beside it, each whole or, where it doesn't
  fit beside it, below it; what doesn't fit in its region goes on at the
  top of the next, before anything else, the content there going around
  it (a sidebar through the next page's banner); a forced break waits for
  it. A block's first children can be set again at the top of each later
  piece of it (`BlockBox.repeatedHead`), and on the piece its floating
  block goes on to.
- Side notes (`FlowLayout.sideNotes`, `sideColumn`): boxes set beside the
  line their anchor is on, in a column of the page's choosing (a reference
  Bible's center column), pushed down where they crowd and carried to the
  next page where they don't fit.
- A region holds as much content as fits with its notes under it (the
  most room found by halving), where it gave up when the notes of what
  fit first took most of the region.
- `LinedContent`: custom content made of lines laid out once per width;
  the layout asks how many fit and keeps as many as the page breaker
  allows (orphans and widows, as for paragraphs), the content placing
  that many. `PageBreaker.linesToKeep` is that rule apart from measuring
  (a page breaker implements it too).
- A table's cell borders can be painted with each cell, before its content
  (`TableBox.borders: TableBorders.withCells`, as prawn-table paints
  them), or after all of it (`TableBorders.above`, the default).
- A block whose content fits a region but whose bottom padding doesn't
  splits there, rather than running past the region's end: its fit was
  checked against its full margin below, where the margin placed is
  clamped to the room left (the random documents of seeds 14, 43 and 50
  laid out again).
- `BoxStyle.splitToRegionEnd`: the piece of a block split across regions
  that a region's end cuts off reaches that end, its background and
  border with it (as engines that draw a block's box after its content
  do), rather than ending under its last child.
  A block whose content runs past the room it was given (a text box's
  last line, its gap below) and whose bottom edge the region's end cuts
  off reaches that end too, rather than running past it.
- `PageTemplate.runningOver`: the header painted after the page's
  content, as the footer is (content reaching into the top margin goes
  under it), rather than before it.
- A table cell is as tall as its content placed: rows were measured with
  the margin above a cell's first block (or a spacer starting it), which
  placing drops, so such a cell had that much room left at its bottom (29
  random documents laid out again). `TableBox.cellsContainMargins` keeps that margin instead,
  as CSS's table cells contain their content's margins.
- Faster, with the same output: math items moved in place and glyph
  metrics cached; a `FlowLayout` keeps its paragraphs' lines and widths
  from one `layout` to the next.
