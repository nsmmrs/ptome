# Changelog

## 0.1.0-dev (unreleased)

- `TextRun.metricsFont`: the font whose metrics a run counts toward its
  line's height instead of its own.

- `TextRun.flushRight`: a run set flush right at the end of the line it
  ends, or on a line of its own, as TeX sets a citation; the line before
  it, ending in its fill, isn't stretched. `LayoutResult.firstText` (a
  page's first line, for a catchword), `LayoutResult.regions` and
  `PieceLine.text`.

- `UprightBox(sideways: true)`: a box turned a quarter to the left on a
  horizontal page, its region its own. Text set with `hist`, `dlig` or
  `hlig` is shaped by the font's layout tables in full, so a contextual
  long s and the discretionary ligatures apply.

- Faster pages of notes in balanced columns: a column set measured with
  no limit (a region's notes, measured for each room its text is tried
  in) is placed once for the same children and width, and a paragraph
  hands out the same rest for the same lines, its line breaks kept;
  output unchanged.

- A tagged table's cells spanning rows or columns carry `RowSpan` and
  `ColSpan` in their structure elements' attributes (PDF/UA-1 7.2).

- `BoxStyle.unnumbered`: a box's lines left out of the line numbering
  of the box it is in (a play's stage directions); `ParagraphContent`'s
  `goesOn`: its first line goes on from the line before it, counted once
  by logical line numbers (FEAT-d1sdfw).

- `MirroredBox`: a box laid out as anywhere else, kept whole, and
  painted turned over about its vertical middle (mirror type;
  FEAT-yq6kff).

- `SplitGraphic`: an inline image that is a piece of something drawn as
  one with the pieces of its `group` beside it on a line
  (`paintPieces`), which the line may break between: a warichu note's
  parts (FEAT-cjd1nv).

- `Paragraph.lineBreak`: how strictly lines break around East Asian
  punctuation and small kana (`LineBreakStrictness`, re-exported), the
  Chinese and Japanese rules where a run's language is either
  (FEAT-cr864h).

- `InlineImage.startOverhang` and `endOverhang`: how far an image reaches
  over what is beside it (ruby's reading over kana); starting or ending a
  line, it is set that much further in (JLREQ 3.3.9) (FEAT-8xyny8).

- Vertical pages (BUG-38zmwk): an upright box too wide for the page (its
  narrowest wider than the page, or its natural width wider than the page
  and within the column's length) is turned to lie along the column
  (JLREQ 2.3.2) instead of squeezed across the page.

- Emoji (FEAT-rr13pg): emoji sequences (ZWJ sequences, skin tones,
  flags, keycaps, U+FE0F) shaped by the font's layout tables in full, a
  character and its variation selector as the font's glyph for the pair
  (`cmap` format 14), as HarfBuzz shapes them (Noto Color Emoji's CBDT and
  COLRv1 builds, both directions); a paragraph's fallback fonts set an
  emoji sequence in the first with color glyphs. `BlendMode` gains the
  non-separable modes. The color test fonts and
  `tool/make_color_test_fonts.py`; `subset_test_fonts.dart` takes font
  names and a `shaped` option.

- Script-specific justification (FEAT-z8hxn0): `Paragraph.
  justificationAlternates` (default on) takes the fonts' `jalt` forms at
  words chosen from the line's end, none side by side, each where it
  fits, before the spaces widen (W3C alreq 7.2.3; `justificationAlternates`;
  Gulzar's forms checked against HarfBuzz); Tibetan lines justify between
  all their characters alike, and `Paragraph.tshegPadding` fills a line
  ending with a tsheg out with tshegs standing for no text (r12a's
  Tibetan notes, which tlreq points to).

- Tai Tham, New Tai Lue, Tai Viet and Ahom are written without spaces
  (FEAT-d2xh7l): a justified line stretches between their syllables.

- JLREQ line adjustment (FEAT-vfmrnj): a justified line with Japanese
  or Chinese is adjusted in JLREQ 3.8's order, each kind of place to its
  limit before the next (`eastAsianPlaces`, `adjustGaps`); the breaker's
  glue has the same limits (a mark's blank half shrinking away).
  `Paragraph.hangingPunctuation` (burasagari, JLREQ 2.5.1: a full stop or
  comma hangs whole past the line's end, first-fit breaking counting what
  hangs too) and `Paragraph.lineStartBrackets` (`LineStartBrackets.solid`,
  `fullWidth`, `novel`: JLREQ 3.1.5). A Japanese line-end closing bracket
  or comma is set solid (JIS X 4051), a full stop keeping its half em.

- Vertical boxes on horizontal pages (TASK-kj6r6q): `VerticalBox` lays
  its child out in a turned frame (vertical-rl or vertical-lr), its
  columns as long as its longest line or its `length`, and places it on
  the page.

- Upright boxes on vertical pages (FEAT-tc0ts6): `UprightBox` lays its
  child out across the page and places it upright in the turned frame, as
  wide as its content needs without wrapping more (at most `maxWidth` or
  the content area's width); one longer than the column upright lies in
  the flow instead (JLREQ 2.3.2, 4.4.2). On a horizontal page it is its
  child.

- Tate-chu-yoko (FEAT-zhqwr3): `TextStyle.combineDigits` sets numbers of
  up to that many digits across a vertical line, upright as one
  character an em long (two in the font's `hwid` forms, three in its
  `twid`, a lone digit in its `fwid`), centred in the column;
  `TextStyle.combineUpright` sets a whole run so (CSS's
  `text-combine-upright`); `TextStyle.combinesAt`. East Asian spacing
  leaves no quarter em beside them.

- Decorations in vertical text (BUG-dfkx3f): `decorationLines(style, y,
  upright:)` places underlines and strike-throughs: the strike-through
  down the em box's middle of upright glyphs and with the letters of
  sideways ones (mirrored in a flipped frame, where it had run beside
  Mongolian's letters); the underline on the right in Japanese and Korean
  (CSS `text-underline-position: right`), the left in Chinese, the right
  in vertical-lr's Mongolian (mlreq 6.2.1).

- Korean word wrapping (FEAT-87x2gw): `Paragraph.wordBreak`
  (`WordBreak.normal`, `keepAll`, `auto`), CSS's `word-break`: `keepAll`
  breaks no word of letters, digits, Han or Hangul (UAX #14's AL, AI, NU,
  ID, H2, H3, JL, JV, JT), a word wider than the line all the same;
  `auto`, the default, keeps Korean runs' words whole (KLREQ 7.1.1).

- Chinese punctuation (FEAT-mcmc8f): `PunctuationStyle` (Japanese,
  mainland, Hong Kong, Taiwan) from `TextStyle.language`, CLREQ's
  conventions: mainland China squeezes marks in a row and sets a closing
  mark ending a line half wide (GB/T 15834-2011 5.1.10, `halt` in the
  text's language); Hong Kong squeezes brackets only; Taiwan none. The
  half-width forms are found in any OpenType font (they had been in
  `OpenTypeShaper` fonts alone).

- Language systems (FEAT-7zjk4y): `TextStyle.language` (BCP 47) maps to
  OpenType language system tags as HarfBuzz 14.6 maps them (its
  registry tables and multi-subtag rules, generated from
  `hb-ot-tag-table.hh`; every entry against `hb_ot_tags_from_script_and_
  language`), and the font's system for it is chosen as HarfBuzz chooses
  it: Japanese, Simplified, Traditional and Hong Kong Chinese glyphs in
  one Noto CJK font, Serbian and Macedonian Cyrillic, Marathi and Nepali
  Devanagari, Urdu and Sindhi digits, glyph for glyph against
  `hb-shape --language`. Text in a language its font has a system for is
  shaped in full; other text as before.

- Vertical writing (FEAT-pwq40f): `TextStyle.vertical` shapes the
  characters that stand upright in vertical text (UAX #50: Han, kana,
  full-width punctuation) top to bottom, as HarfBuzz's TTB direction does
  (`vert` forms, vertical advances and origins, glyph for glyph against it
  in every left-to-right script), the rest on their side;
  `ShapedGlyph.upright` and `copyWith`. `PageTemplate.writingMode`
  (`WritingMode.verticalRightToLeft` for Japanese and Chinese,
  `verticalLeftToRight` for Mongolian): the content laid out in the
  content area turned a quarter turn, painted turned back (anchors and
  links where they are drawn), images standing upright;
  `TextStyle.flipped` mirrors text back in vertical-lr's mirrored frame.

- Emphasis marks (FEAT-2q4rln): `TextRun.emphasisMark` and
  `emphasisUnder`, CSS's `text-emphasis`: a mark over (or under) each
  character but spaces and punctuation, CSS's own marks drawn as shapes
  (dot, circle, double circle, triangle, sesame; filled or open), the
  line taller (or deeper) by `emphasisExtent`; `paintEmphasisMarks` for
  other text.

- East Asian composition (FEAT-x45qvj), from JLREQ and CLREQ, on by
  default (`Paragraph.eastAsian`): of two full-width punctuation marks in
  a row one is set half wide by the font's `halt` (as OpenType's `chws`
  would, for fonts without it); a quarter em between Han or kana and a
  Latin letter or digit, also between runs; a justified line written
  without spaces stretched between its characters (Thai, Lao, Khmer and
  Myanmar between their words), as much at each as at a space, and the
  breaker given that stretch. Kinsoku is UAX #14's, checked. The CJK
  features (`chws`, `halt`, `palt`, `vert`, `vrt2`) shape as HarfBuzz
  does, and the HarfBuzz test now passes features to the native oracle
  (it dropped them).

- Hyphenation in the shaped scripts (TASK-1wlzq5): a word with vowel
  signs, viramas or combining accents is hyphenated (only words of class
  AL and HL letters were, so no Indic word ever was; BUG-9t3kgj), and a
  line's hyphen in a fully shaped script is drawn, the font's hyphen
  standing for the soft hyphen (full shaping hid it as a default
  ignorable; BUG-0rtx6p). Every language with patterns for a shaped
  script (Indic, Coptic, Georgian, Ethiopic, Thai, polytonic Greek) is
  checked: each place leaves two halves that shape without a dotted
  circle, no conjunct divided.

- Kashida (FEAT-01jjv7): `Paragraph.kashida`, how far each word of a
  justified line of Arabic may be lengthened by tatweel, in em, before
  the spaces widen. Each word at its best-ranked place (Microsoft's
  ranking for Arabic justification), never inside Lam-Alef or off the
  baseline; the tatweel drawn as one glyph or several overlapping, exact
  to the width, standing for no text.

- The Universal Shaping Engine (Sinhala, Tibetan, Mongolian, N'Ko,
  Javanese, Balinese, ...; the joining scripts' forms by the Arabic
  joining), and the Khmer, Myanmar, Thai/Lao and Hangul shapers,
  HarfBuzz 14.6's, each glyph for glyph against it; Persian and Urdu in
  Naskh and Nastaliq too. Text of a right-to-left script is shaped right
  to left whatever the caller asks, given back in logical order, so it
  measures as wide as it is set (Nastaliq measured left to right was a
  quarter of its width). A default ignorable a substitution replaced is
  no longer skipped or hidden, as in HarfBuzz.
- The Indic shaper (HarfBuzz 14.6's): Devanagari, Bengali, Gurmukhi,
  Gujarati, Oriya, Tamil, Telugu, Kannada and Malayalam shape glyph for
  glyph as HarfBuzz does, in fonts of the second and the first
  specification; the syllable grammars scanned as Ragel scans them, dotted
  circles in broken syllables and prohibited vowel sequences. Its tables
  are generated from HarfBuzz's (`tool/harfbuzz_tables.dart`). The script
  tests use a full HarfBuzz build as their oracle when it is built
  (`tool/oracles/harfbuzz-native`).
- Shaping is HarfBuzz 14.6's pipeline (`lib/src/shaping/`): the plan
  (the script's tags, the shaper, the features in their stages with
  pauses), normalization (decomposed and recomposed as the font has the
  characters, marks in HarfBuzz's order), the shaper's masks, GSUB, then
  GPOS and the marks' widths. Text with marks, or in any script but
  Latin, Greek and Cyrillic, takes it; Cyrillic, polytonic Greek,
  Vietnamese, Armenian, Georgian, Coptic and Ge'ez shape glyph for glyph
  as HarfBuzz does (`test/harfbuzz_scripts_test.dart`), as Arabic and
  Hebrew did.
- HarfBuzz's licence (`vendor/harfbuzz/COPYING`), published with the
  package: the shaper follows HarfBuzz's features, their order and its
  Arabic shaper's rules.
- A note referred to in a block floating to a side is set where the
  block goes on in the next region (it was left out: the notes of the
  float's piece set at a region's top weren't counted). In the random
  flow documents, 34 notes in 14 of them.
- `LineHeight.font(skip:, lineSkip:)` and `FontLineHeight.apart`: lines
  a baselineskip apart (TeX's interline glue, The TeXbook ch. 12),
  whatever fonts they mix: a line's baseline [skip]'s height and the
  leading below the one above's, moved down only by as much as its text
  and the depth of the line above are taller than the skip's (its
  `\lineskiplimit` and `\lineskip` the skip's own gap and leading), so
  a theme's leading, a negative one too, holds.
- `KnuthPlassLineBreaker` keeps breaks apart by their line numbers only
  up to TeX's easy line (§848), from which every line is as wide: a long
  justified paragraph of wide words (Arabic set in a font without it,
  each letter an em-wide `.notdef`) is broken in a fraction of a second
  rather than minutes, its breaks the same.
- `Canvas.glyphs` takes `text`: what the glyphs stand for as drawn, a
  right-to-left run's characters reversed, for a backend that maps glyphs
  back to text. A line's `TextFragment`s say whether they are a
  right-to-left run's (`rightToLeft`), and are painted with their text.
- `ParagraphContent.textTaken`: how much of a paragraph's text its first
  lines take (in its runs' text), whether a hard break ends them and
  whether a hyphen does, for setting a first line apart.
  `Paragraph.alignLast: TextAlign.justify` stretches the last line (and
  those before a hard break) as CSS's `text-align-last: justify` does; a
  paragraph that ends in a soft hyphen shows it, as a line hyphenated
  there does.
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
