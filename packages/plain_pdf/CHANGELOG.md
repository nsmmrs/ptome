# Changelog

## 0.1.0-dev (unreleased)

- Color glyphs (FEAT-rr13pg): text in a font with color glyphs (`COLR`,
  `CBDT`, `sbix`) draws them as the font paints them, each once as a form
  (shadings for gradients, transparency groups, soft masks and blend
  modes for composites, images for bitmaps), shown as codes of a Type 3
  font with a ToUnicode map: an emoji sequence reads back as written.
  Checked against HarfBuzz's own painting through cairo
  (`tool/oracles/harfbuzz-cairo`), rasterized by Poppler. `softMask`
  takes `invert`; `BlendMode` has `hue`, `saturation`, `color` and
  `luminosity`.

- `PdfWriterOptions.dates`: false leaves the creation and modification
  dates out of the document information and the XMP metadata (a
  reproducible file); `xmpPacket` takes a null date for none
  (BUG-d2dtqb).

- Vertical text: an upright glyph is drawn turned back a quarter turn
  about its vertical origin, centered on the line; flipped text
  (`TextStyle.flipped`) mirrored about its em box's middle
  (FEAT-pwq40f).

- A glyph shown for several characters (a space's glyph standing for a
  no-break space the font lacks) reads in the ToUnicode map as the
  character the font's cmap gives it, not as the first it showed.
- Images of the same file share one XObject, however many `PdfImage`s of
  it the pages draw (each file hashed once): a logo on every page was an
  XObject a page.
- Images are read by the new plain_images package (PNG decoding moved
  there with its history): `PdfImage.parse` takes any file it reads
  (JPEG, PNG, GIF, BMP), and `PdfImage(ImageFile)` one already read.
  JPEG and PNG are written as before, byte for byte (checked on PngSuite
  and the JPEG test images, compressed and not), but for JPEG files
  DCTDecode doesn't read (12-bit, arithmetic-coded, lossless), which are
  now decoded instead of written as invalid DCTDecode streams; other
  images are
  decoded, a palette kept as an indexed color space, a transparent color
  as a color-key mask, alpha as a soft mask. `JpegImage`, `PngImage`,
  `PngColorType` and `ImageFormatException` are plain_images' now
  (`JpegFile`, `PngFile`, ...); `PngPayload` is `ImagePayload`, made by
  `encode` for any image that `reencodes`; `bitsPerComponent` is the
  XObject's. `readSvgRaster` reads any of them.
- SVG moved to the plain_svg package with its history (`SvgImage`,
  `SvgPath` and the path segments), which draws on any canvas; plain_pdf
  no longer depends on `xml`. `PdfCanvas` implements plain_svg's
  `SvgCanvas`: a transparency group as a form, a gradient as an axial or
  radial shading, a luminosity mask as a soft mask. `standardSvgFont`
  (the standard fonts for an SVG's families, as the SVG reader chose
  them by default) and `readSvgRaster` (a JPEG or PNG for an SVG's
  `<image>`). `SvgImage.draw(PdfCanvas, ...)` is `paint(Canvas, ...)`.
  SVG drawn in a PDF is checked against resvg's 1,742 reference renders
  (`test/resvg_test.dart`, nightly, after `tool/fetch_resvg_tests.sh`):
  735 drawn alike, recorded in `test/resvg_baseline.txt`.
- Glyphs are drawn at the advances shaping gave them: where it changed
  one (right-to-left positioning folded into advances), the pen moves by
  that, not by the font's width (`EmbeddedFont.glyphAdvance`); a Hebrew
  line no longer ran up to 0.6 em past its measure.
- `EmbeddedFont.parse(typoMetrics:)` / `.shaped(typoMetrics:)`: the
  ascender, descender and line gap from `OS/2`'s typographic metrics
  where the font has them (as Prawn measures fonts), not `hhea`'s.
- `EmbeddedFont.missingCharacters`: the characters text used that the
  font has no glyph for.
- Shaped text taken from the page reads as written. `PdfCanvas.glyphs`
  takes the glyphs' `text` as drawn, and marks with it as their actual
  text (ISO 32000-2, 14.9.4) the glyphs a font's ToUnicode map can't read
  so: a glyph standing for no text (an Arabic letter's dots, drawn apart
  from their dotless base), one the map reads as another (a base shared
  by several letters), marks moved onto their base (which extraction
  sets apart). A run that starts with marks is drawn base first, at the
  same places, so it is read on its line. `EmbeddedFont.readsAsShown`
  says whether the map reads glyphs as their own text; a single-byte font
  gives a glyph a code for each text it stands for. The Qur'an in Noto
  Naskh Arabic: pdftotext gives every verse as written (none did, with
  143,435 U+FFFD); a pointed Talmud page, 2,040 of 2,045 words (112).
- `ImportedPage.content`, a page's content read back (its streams
  decoded and joined), is public: what a test reads to check where text
  was set.
- A glyph's x and y offsets are drawn (an Arabic or Hebrew mark on its
  base): the pen moved in the `TJ` array and a run of raised glyphs given
  its own rise. A single-byte font's runs still draw glyphs at their pen
  positions. `PdfFont.shape` takes `rightToLeft`; a standard font
  reverses the run, unshaped.
- Tagged PDF (`PdfDocument(tagged: true)`): a page's canvas is a
  `StructureCanvas`, its content marked as the elements it is told it is
  (an MCID each) or as artifacts; the document gets its structure tree
  (marked content and link annotations as each element's kids, a
  `Document` root), the parent tree, `/MarkInfo`, each page's
  `/StructParents` and `/Tabs /S`, each link a `Link` element with its
  annotation described (`/Contents`). `PdfInfo.pdfuaPart` writes PDF/UA's
  identification in the XMP metadata.
- `.notdef`, shown for a character a font lacks, reads as U+FFFD in the
  ToUnicode map (every glyph shown maps to text, as PDF/UA has it).
- `EmbeddedFont.shaped`: an embedded font from a parsed font's shaper,
  shared by the documents that embed it (its kerning too).
- `EmbeddedFont.parse(singleByte: true)` writes a font with TrueType
  outlines as simple TrueType fonts of up to 256 glyphs each, a byte a
  glyph and the space code 32 in each, with their own `cmap` and
  ToUnicode map and no encoding (symbolic, so no viewer reads the codes
  as another encoding's): the canvas shows text in runs of one subset
  (`encodeRuns`, `Tf` between them) and word spacing as `Tw`.
- `SvgImage.parse(scalesAboutPageOrigin: true)` places a uniformly scaled
  image as one drawn at its own size and scaled about the page's origin
  is, the scale and the translation each to five decimals (as prawn-svg
  places it).
- The standard Latin fonts set the no-break space and the soft hyphen as
  the space and the hyphen, as WinAnsiEncoding encodes them a second time
  (ISO 32000-2, Annex D.2); they had no glyph.
- Text set with word spacing places its words as a `Tw` operand would:
  the spacing to a hundred-thousandth of a point, and the `TJ` adjustments
  written to five decimals (they were rounded to three: positions drifted
  by up to a few hundred-thousandths of a point along a line).
- Layout moved to plain_typesetting with its history: paragraphs and the
  line breakers, `FlowLayout` and its boxes, the math layout, geometry,
  colors, `TextStyle`, `Graphic`, `ShapedGlyph`, and the shaping loop of
  embedded fonts. plain_pdf depends on it and no longer exports them;
  `PdfRect`, `PdfMatrix`, `PdfColor` and `PdfTextStyle` are now
  `Rect`, `Matrix`, `Color` and `TextStyle` there.
- `PdfCanvas` implements plain_typesetting's `Canvas`, `PdfPage` its
  `LayoutPage`, `PdfDocument` its `LayoutDocument` (`addAnchor` makes an
  XYZ destination), `PdfFont` its `Font` and `EmbeddedFont` its
  `OpenTypeTextFont`; PDF images, imported pages and SVG images paint on a
  `PdfCanvas` (`pdfCanvasOf`). `LinkTarget.destination(...)` is now
  `DestinationTarget(...)`. The PDFs written are the same, byte for byte.
- The MathML tree (`MathNode` and its kinds, `parseMathML`,
  `MathMLException`) moved to plain_math with its history, and the
  OpenType MATH table (`OpenTypeMathTable`, `MathConstant`,
  `MathVariant`, `GlyphConstruction`, `GlyphPart`) to plain_fonts;
  plain_pdf depends on both and no longer exports them. A formula's `mathcolor` is parsed as a CSS color by the
  math layout.
- `PatternHyphenator` moved to plain_hyphenation with its history;
  plain_pdf keeps the `Hyphenator` interface its paragraphs take.
- Line breaking (UAX #14) moved to plain_unicode with its history;
  plain_pdf depends on it and no longer exports `lineBreaks`,
  `lineBreakClass`, `LineBreak`, `LineBreakClass` and `unicodeVersion`.
- Renamed from `libpdf` to `plain_pdf`, and moved with its history into the
  ptome pub workspace (github.com/nsmmrs/ptome, `packages/plain_pdf`;
  ptome's ADR-0018). It no longer re-exports `OpenTypeFont` and
  `FontFormatException`; import them from plain_fonts. `libpdfVersion` is
  `plainPdfVersion`.
- The repository: package layout, analysis, CI (Linux, macOS, Windows, and
  a JavaScript compile of the library), the layered design (ADR-0001).
- The object layer: the PDF object model as sealed types (null, boolean,
  integer, real, string, name, array, dictionary, stream, reference) with
  their syntax; Flate (DEFLATE with dynamic Huffman codes, and inflate) in
  pure Dart, so output is the same bytes on the VM and the web (MD5 from
  package:crypto); a
  streaming writer with cross-reference tables, or cross-reference and
  object streams, document information and XMP metadata, file identifiers,
  and a deterministic mode. Checked with `qpdf --check` and poppler.
- Fonts: OpenType parsing (TrueType and CFF outlines, collections, cmap
  formats 0, 4, 6 and 12, kerning from `kern` and GPOS pair adjustment,
  `liga` ligatures from GSUB); TrueType subsetting that keeps glyph ids;
  embedding as Type0/Identity-H fonts with widths and a ToUnicode map, so
  text stays extractable; and the 14 standard fonts with metrics, kerning
  and WinAnsi encoding generated from the Adobe AFM files. CFF fonts are
  embedded whole for now.
- Web fonts: WOFF and WOFF2 fonts embed as the fonts they wrap.
- Font reading and subsetting moved to the plain_fonts package, and
  DEFLATE, zlib and Brotli to plain_compression, with their history;
  plain_pdf depends on both. `adler32`, `deflate`, `inflate`, `zlibEncode`
  and `zlibDecode` now come from plain_compression.
- Images: JPEG files embedded as they are (DCTDecode; gray, RGB and CMYK,
  baseline and progressive, Adobe-inverted CMYK, EXIF orientation
  reported); PNG files of every color type and bit depth, embedded as they
  are when PDF can show them (FlateDecode with a PNG predictor), decoded
  otherwise: interlaced images, alpha split into a soft mask, palette
  transparency, color-key transparency, embedded ICC profiles; damaged
  files rejected. Checked against PngSuite by rendering with poppler.
  Decoded images are filtered again for their stream with each filter
  scored in its own loop, stopping once it can't win.
- Drawing: `PdfDocument` with pages (media, crop, bleed, trim and art
  boxes; rotation) drawn on a `PdfCanvas`: paths (lines, Bézier curves,
  rectangles, rounded rectangles, ellipses), fill and stroke with the
  nonzero or even-odd rule, clipping, gray, RGB, CMYK and spot colors,
  line width, caps, joins, miter limit and dashes, transforms and
  save/restore; opacity, blend modes, soft masks and transparency groups;
  reusable forms; images; text at explicit positions with kerning,
  character and word spacing (also for embedded fonts), rise, horizontal
  scaling and render modes, measured as drawn. Links (URIs, named and
  explicit destinations), named destinations, outlines with nesting and
  styles, page labels, page mode, language and viewer preferences. Each
  document declares the lowest PDF version it needs.
- Speed, with the same bytes: content streams are written straight to
  bytes, numbers formatted with integer math (`formatNumber` decides only
  next to a rounding tie); standard fonts kern from a flat table, and
  text runs go into `TJ` without copies; PNG rows are unfiltered with a
  loop per filter, and opaque alpha is found while it is split out; SVG
  path data is scanned by hand, not with regular expressions.
- Layout, paragraphs: break opportunities by the Unicode Line Breaking
  Algorithm (UAX #14, Unicode 18.0; the conformance test passes), styled
  text runs and inline images as boxes, glue and penalties, line breaking
  as a strategy (`LineBreaker`) with first fit and Knuth-Plass provided,
  soft hyphens and a hyphenation hook, words wider than the line broken
  anywhere, alignment (left, center, right, justified), first-line indent,
  line heights (font, multiple, exact), underline and strikethrough from
  the fonts' metrics, links and anchors reported where they are painted.
- Layout, pages: a box tree (blocks with margins, padding, borders and
  backgrounds; paragraphs; images; spacers; drawings; page and column
  breaks; column sets) flowing into the regions of page templates (with
  columns), split where needed (a split block's border stays open, and
  its bottom padding and border take room only below its last child), with
  keep-together, keep-with-next, orphans and widows decided by a
  `PageBreaker` strategy; running headers and footers that see the page
  number, the page count and running marks; anchors that become named
  destinations; page references resolved by laying out again.
- Layout, tables: fixed, fraction and auto column widths (auto columns
  share space by their content's narrowest and widest widths, as CSS's
  automatic table layout does), column and row spans, per-cell padding,
  backgrounds, borders and vertical alignment, header rows repeated on
  each page, row groups joined by spans kept together, and rows (and
  spanning cells) split when taller than a page. Inline decorations
  (background and border behind a run). A sample document with golden
  renders, and a benchmark (`benchmark/layout_benchmark.dart`, about 240
  pages a second on a laptop).
- Font fallback chains: a text run's characters its font lacks are set in
  the first of its fallback fonts that has them.
- SVG: `SvgImage` draws SVG as PDF vector graphics: the path grammar
  (arcs included), basic shapes, transforms, nested viewports with
  viewBox and preserveAspectRatio, `use` and `symbol`, fill and stroke
  styles, linear and radial gradients (shadings; stop opacity as a soft
  mask), clip paths, group opacity (transparency groups), a CSS subset
  (style sheets with type, class, id and descendant selectors; style
  attributes), text in PDF fonts with anchors and baselines, raster and
  SVG images from data URIs or a resolver. Masks, filters, markers,
  patterns and per-character text positions are reported as warnings.
  Checked against librsvg's renderings. Shadings (`AxialShading`,
  `RadialShading`, `PdfCanvas.shade`) join the drawing API; `Graphic`
  lets the layout place raster and SVG images alike.
- The package: only the supported API is exported (internals of the
  canvas and shadings are no longer public), checked against a snapshot in
  CI (`tool/api_check.dart`); examples (a styled report with a table of
  contents, an SVG chart, a two-column booklet) run as tests;
  `FlowLayout.startTemplate` chooses the first page's template.
- `CustomBox`: content that lays itself out (`CustomContent`), placed and
  split by the layout like any box, for callers reproducing another
  engine's text boxes.
- Fonts: `EmbeddedFont.parse(truncateWidths:)` writes glyph widths
  truncated rather than rounded (text then lines up with engines that
  truncate); OS/2 typographic metrics; `kern` table pairs;
  `StandardFont.boundingBox`.
- `BoxStyle.decoration`: a callback painting over each piece of a block,
  told whether the piece is where the block starts and ends.
- `BreakBox.page(force: true)` and `BreakBox.column(force: true)`: a
  break made even at the top of a region.
- `ColumnWidth.computed`: a table column whose width is computed from the
  table's width.
- `SvgImage.rootAttribute`: the root element's attributes as written.
- `FlowLayout(keepTemplate: true)`: a page break's template stays in
  effect for the pages after it, and a break to a template at the top of
  an empty page replaces it; `PageInfo.template` names a page's template.
  The top of each column of a `ColumnsBox` is a region top (breaks and
  top margins there count for nothing). A last page with nothing on it
  (after a trailing page break) is left out.
- `kernTablePair(subtable:)` and `EmbeddedFont.parse(kernTableSubtable:)`:
  kerning from one subtable of the `kern` table alone (Prawn kerns with
  the first).
- Tables: `TableCell.verticalOffset` places a cell's content by a
  function of the room and the content's height, `TableCell.decoration`
  paints a cell's border in place of `border`, and `TableBox.stripes`
  gives body rows backgrounds in turn, starting over in each region.
- Reading: `PdfFile.parse` reads a PDF file's objects (cross-reference
  tables and streams, incremental updates, object streams; rebuilt by
  scanning the file when the cross-references are broken; Flate, LZW,
  ASCIIHex, ASCII85 and RunLength filters with PNG predictors) and its
  pages; an `ImportedPage` paints into another document as a form XObject
  of the page's content, with its resources copied once (`PdfCanvas.page`),
  turned as the page is displayed. Encrypted files are rejected.
- A template break that replaces an empty page carries what was placed on
  it (anchors, marks) to the page replacing it.
- `BreakBox.page(side:)`: content after the break starts on a recto (odd)
  or verso (even) page, after a blank page when needed (`PageSide`);
  `FlowLayout(templateForPage:)` gives each page its template by number,
  for margins that differ between recto and verso pages.
- A custom box paints its style's decoration under its content.
- `PageTemplate.foreground` paints over a page's content, header and
  footer. `PdfDocument.openAction` (where the document opens),
  `PdfDocument(nonFullScreenPageMode:)` and `PdfDestination.fitHeight`
  (`FitV`).
- `SvgImage.parse(defaultFontFamily:, fallbackFontFamily:)`: the family
  of text without a `font-family`, and a family tried after an element's
  own.
- CFF fonts are subset: the glyphs used keep their charstrings and glyph
  ids, the others become empty, and so do the subroutines (local and
  global) no kept glyph calls; a CID-keyed font gets an identity charset,
  as text addresses glyphs by id. The CFF is embedded bare
  (`CIDFontType0C`). Fonts with CFF outlines no longer fail to embed (the
  glyph closure read TrueType composites). A CFF that can't be rewritten
  (`seac` accents, damaged) and CFF2 are embedded as they are.
- `LayoutResult.render(destinationName:)` names the destinations of the
  anchors.
- A fuzz test (seeded) damages JPEG, PNG, SVG, font and PDF input: every
  decoder either reads it or rejects it with its format exception. Fixed
  on the way: a damaged font could fail with a RangeError (the name table,
  table and glyph slices, composite glyphs), a PDF file with a damaged
  Flate stream or a truncated dictionary likewise, and an SVG image whose
  data URI had a bad percent escape failed the whole SVG.
- Faster text: standard-font kerning by code, number formatting without
  regular expressions, `TJ` written without per-glyph allocations, copying
  byte builders, embedded-font kerning pairs cached. BASELINE.md compares
  plain_pdf with package:pdf.
- `PatternHyphenator`: Liang's hyphenation over TeX patterns and
  exceptions (as hyph-utf8 distributes them), with the fewest letters
  before and after a hyphen; a `Hyphenator` for paragraphs.
- `FlowLayout(notes:, noteSeparator:)`: notes (footnotes) by the anchor
  that refers to them, set at the bottom of the region the anchor is
  placed in, the region's content making room; a note that doesn't fit
  goes on in the next region.
- `BoxStyle.float` (`FloatPlacement`): a box that doesn't fit where it
  is goes to the top of the next region, the content after it filling the
  room (a figure); one that fits goes to the top or the bottom of its
  region (`top`, `bottom`, `auto`: the nearer), the content flowing around
  it, or stays (`next`). `BoxStyle.floatBarrier` keeps a box (a heading)
  after the floating boxes waiting.
- `BoxStyle.verticalAlign`: a block that starts a region and fits in it
  whole sits in the middle or at the bottom of the room (a dedication
  alone on its page).
- `PdfTextStyle.skew` and `PdfTextStyle.embolden`: text slanted (an
  oblique face made from an upright one) and stroked (a bold face made
  from a regular one).
