# Changelog

## 0.1.0-dev (unreleased)

- `selectLanguage`, `hasLanguageSystem`, and `featureLookups` /
  `requiredFeature` with a `language`: the language system HarfBuzz's
  `select_language2` chooses (a requested one, else `dflt`, else the
  script's default) (FEAT-7zjk4y).

- Vertical metrics (FEAT-pwq40f): `verticalAdvance` and
  `verticalOriginY`, as HarfBuzz reads them (`vmtx`, `VORG`, the top
  phantom point of TrueType outlines, the glyph centered without them).
  `position(vertical: true)`: GPOS top to bottom (y advances growing
  downward, value records' y advances, marks attached across).

- A multiple substitution's glyphs keep their source's character and
  categories (a split vowel's pieces stay vowels for the shaper).
- `OpenTypeLayout.wouldSubstitute`: whether a GSUB lookup would
  substitute a glyph sequence as a whole (HarfBuzz's
  `hb_ot_layout_lookup_would_substitute`), for the Indic shaper.
- `OpenTypeLayout` matches as HarfBuzz does: each glyph has its
  properties (`GlyphProps`: its class from GDEF, or as its shaper guesses
  it, and what substitutions made it), its syllable and what its
  character is (`UnicodeFlags`); lookups (`LayoutLookup`) skip joiners or
  not, and match within a syllable or not; a substitution updates the
  glyph's class; `selectScript`, `featureLookups`, `requiredFeature` and
  `searchFeature` choose the script and features as HarfBuzz's map does.
- HarfBuzz's licence (`vendor/harfbuzz/COPYING`), published with the
  package: the OpenType layout follows HarfBuzz where the specification
  leaves it open.
- `OpenTypeLayout`: a font's GSUB and GPOS lookups applied in full, for
  the scripts that shape (Arabic, Hebrew): the lookups of a feature for
  a script and language, every substitution type (single, multiple,
  alternate, ligature, contextual, chained, extension, reverse chained)
  and positioning type (single, pair, cursive, mark to base, ligature
  and mark, contextual, chained, extension), GDEF's glyph classes and
  mark filtering, on `LayoutGlyph` runs that keep their clusters,
  ligature components and attachments.
- A TrueType subset's checksums are OpenType's: the head table's own
  taken with its checkSumAdjustment 0, and the file summing to
  0xB1B0AFBA. The adjustment was added into the head table's record too,
  so neither held. Every subset's bytes change.
- `FontIndex.over`: fonts given as bytes over another index, whose
  folders aren't walked nor fonts read again.
- `subsetTrueType(codes:)`: a `cmap` mapping one-byte codes to the
  glyphs they show (Macintosh Roman and Windows symbol subtables), for a
  font embedded in a PDF as a simple font.
- Faster, with the same output byte for byte: CFF subsets in one pass
  (a CJK font's 100-glyph subset 60 to 7 ms), TrueType subsets assembled
  once, WOFF2 glyf rebuilt into one buffer, GPOS kerning through
  typed-array accelerators (about 20 times faster per uncached pair),
  `glyphFor` without building the `characterMap` Map, `FontIndex.find`
  and `hasFamily` by family key (microseconds instead of a millisecond
  with 780 fonts), and a cold font index scan opening each file twice.
- A read past the end of a font's data is still a `FontFormatException`,
  now with the message "read past the end of the font" (without the
  offset).
- The OpenType MATH table (`OpenTypeMathTable`, `MathConstant`,
  `MathVariant`, `GlyphConstruction`, `GlyphPart`) from plain_pdf, with
  its history.
- Renamed from `fonts` to `plain_fonts`, and moved with its history into the
  ptome pub workspace (github.com/nsmmrs/ptome, `packages/plain_fonts`;
  ptome's ADR-0018).
- OpenType reading (TrueType and CFF outlines, collections, cmap formats
  0, 4, 6 and 12, `kern` and GPOS kerning, GSUB substitutions), TrueType and CFF subsetting, and WOFF and WOFF2 decoding,
  extracted from plain_pdf with their history.
- The installed-font index, from asciidart: fonts by file name or by
  family and style, in the platform's font folders (the Dart VM, Node.js)
  or files an embedder gives, their headers cached; WOFF and WOFF2 fonts
  decoded (on JavaScript, by a part loaded on demand).
