# Changelog

## 0.1.0-dev (unreleased)

- Case mapping by language (FEAT-8b8z4k): `upperCase` and `lowerCase`
  take a `language` (BCP 47) and apply SpecialCasing.txt's tailorings:
  Turkish and Azeri dotted and dotless i (`i` to `İ`, `I` to `ı`, a
  capital I with a dot above to `i`), Lithuanian's dot above kept under
  accents and removed after a soft-dotted letter (Soft_Dotted from
  PropList.txt, now vendored). Checked against ICU 78.3's
  `u_strToUpper`/`u_strToLower` on random text (`tool/oracles/icu`).

- Word breaking without spaces (FEAT-hpr7b0): `lineBreaks` and
  `lineBreakOffsets` break runs of Thai, Lao, Khmer and Myanmar between
  their words, as ICU 78.3's dictionary break engines do (its word lists,
  brotli-compressed, under the Unicode License in `vendor/icu/LICENSE`;
  its lookahead, its joining of non-words and its Thai suffixes), unless
  `dictionary: false`. Checked against ICU's line break iterator on
  random text (`tool/dictionary_fuzz.dart`, the oracle in
  `tool/oracles/icu`), every break the same in 270,000 lines; a golden
  file keeps the check without ICU.

- Shaping properties (Unicode 18.0.0): `generalCategory`, `scriptOf`,
  `indicSyllabicCategory`, `indicPositionalCategory`,
  `verticalOrientation`, `isDefaultIgnorable`, `isMark`, and canonical
  decomposition and composition (`canonicalDecomposition`,
  `canonicalComposition`), checked against NormalizationTest.txt.
- The Unicode License (`vendor/ucd/*/license.txt`) is published with the
  package, as the tables generated from the Unicode data are under it
  (it was left out with the data).
- The Unicode Bidirectional Algorithm (UAX #9, Unicode 18.0.0):
  `BidiText`, each code unit's embedding level in its paragraph (the
  base direction given, or the first strong character's), a line's
  levels with its trailing whitespace set back (L1) and its runs or
  characters in visual order (L2); explicit embeddings, overrides and
  isolates, and bracket pairs (N0). It passes BidiTest.txt and
  BidiCharacterTest.txt. The Bidi_Class, Bidi_Mirroring_Glyph and
  Joining_Type properties (`bidiClass`, `bidiMirror`, `joiningType`),
  and the Canonical_Combining_Class (`canonicalCombiningClass`),
  generated from the Unicode data. `hasRightToLeft`: whether a text
  takes the algorithm.
- Line breaking (UAX #14, Unicode 18.0.0), moved from plain_pdf with its
  history; it passes LineBreakTest.txt.
- Full case mapping (Unicode 17.0.0), generated from UnicodeData.txt and
  SpecialCasing.txt: `upperCase`, and `lowerCase` with or without the
  Final_Sigma rule, checked against Ruby 4.0.7 and Node.js for every code
  point. It replaces ptome's Ruby-generated table and plain_highlighting's
  use of the platform's tables.
- Line breaking is faster, with the same breaks: the line break
  properties are a three-stage table (25.7 KB of data, ICU's layout)
  instead of a binary search over 3,851 ranges, with the class the rules
  use resolved at generation time. `lineBreakClass` takes 5.5 ns instead
  of 16. The rules run over integer classes in reused typed lists, with no
  object per character and no closure per pair: `lineBreaks` takes about
  29 ns per code unit of English instead of 67.
- `lineBreakOffsets(text)`: the breaks of `lineBreaks` without an object
  for each, as a `LineBreakOffsets` (an extension type over one
  `List<int>`: `length`, `offsetAt`, `isMandatoryAt`). plain_typesetting's
  `paragraphItems` walks it with a cursor instead of probing two
  `Set<int>`s per character.
- Line breaking answers most pairs of classes from two 64x64 tables (one
  for pairs after spaces), filled by running the rules themselves, and
  leaves the pairs that need more context to the rules. A permanent test
  checks the tables against the rules. `lineBreakOffsets` takes about
  9 ns per code unit of English, 12 of Japanese (56 and 75 before these
  changes).
