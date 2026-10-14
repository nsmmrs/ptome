# Changelog

## 0.1.0-dev (unreleased)

- Line-breaking strictness (FEAT-cr864h): `lineBreaks` and
  `lineBreakOffsets` take a `LineBreakStrictness` (CSS Text 3's
  `line-break`: `strict`, UAX #14's rules; `normal`; `loose`; `anywhere`)
  and whether the text is Chinese or Japanese; checked against ICU
  78.3's `lb` keyword. The wide prefixes and suffixes (PR and PO of
  East_Asian_Width A, F or W) come from the UCD with the other tables.

- Dates (FEAT-f7cn49): `formatDate`, `formatTime` and `formatDateTime`
  write a moment as a language does, in CLDR 48.2's Gregorian patterns
  of each `DateStyle` (month and day names, day periods with their
  rules, eras, localized GMT offsets, the "at" date-time patterns, a
  pattern's own numbering), the language's digits or a numbering
  system's (`vendor/cldr/48.2.0/gregorian.tsv` and `day_periods.tsv`,
  written by `tool/import_cldr_gregorian.py`). Checked against ICU 78.3's
  DateFormat for every locale ICU carries at CLDR's basic coverage or
  more (`tool/oracles/icu/icudate`).

- Counter styles (FEAT-ndn74f): `CounterStyle` writes numbers in the
  counter styles of CSS Counter Styles Level 3 (its predefined styles, the
  longhand Chinese, Japanese and Korean styles, Ethiopic numerals) and the
  W3C's Ready-made Counter Styles, 203 in all (`vendor/w3c`), with their
  prefixes, suffixes, ranges and fallbacks; `cssRule` as a CSS rule,
  `forNumberingSystem` the style of a CLDR numbering system.
  `defaultNumberingSystem` (CLDR 48.2's `defaultNumberingSystem`, `-u-nu-`
  honored), `numberingSystemDigits` and `formatDigits`. Checked against
  the specification's tables and WeasyPrint 70's `counter()` and markers
  (`tool/oracles/weasyprint`).

- `vendor/icu/LICENSE` keeps the parts of ICU's LICENSE that apply to the
  word-break dictionaries taken (the Unicode License, ICU's older licence,
  the Lao and Burmese dictionaries' notices), not those for ICU4C's and
  ICU4J's build files and other data.

- Emoji (FEAT-rr13pg): `isEmoji`, `isEmojiPresentation`,
  `isEmojiModifier`, `isEmojiModifierBase` and `isExtendedPictographic`
  (emoji-data.txt, Unicode 18.0.0), and `emojiSequenceLength`: where an
  emoji presentation sequence (UTS #51 ED-17) starts and ends, checked
  against every sequence of emoji-test.txt.

- Collation (FEAT-5ttjh1): `Collator(language)` orders text by the
  Unicode Collation Algorithm (UTS #10, Unicode 17) with CLDR 48.2's root
  order and each locale's tailoring (113, `-u-co-` types such as
  `zh-u-co-stroke`), compiled from CLDR's rules: `compare`, `sortKey`
  (`CollationKey`), and an index's headings (`indexLabels`,
  `indexLabel`) as ICU's AlphabeticIndex has them (pinyin letters,
  stroke counts, kana rows). Checked against CLDR's conformance test
  (every line) and ICU 78.3's collator on every tailoring it has
  (`tool/oracles/icu/icucoll`, `icuindex`). The rules are vendored in
  `vendor/cldr/48.2.0/collation` (Unicode License v3);
  `tool/generate_collation.dart` compiles them.

- Syllable breaks (FEAT-d2xh7l): Tai Tham, New Tai Lue, Tai Viet and
  Ahom (SA, no ICU dictionary, no word list under a permissive licence)
  break between orthographic syllables, from their Indic syllabic and
  positional categories: before a consonant, an independent vowel or a
  vowel written before its consonant; not after a prevowel or Tai Tham's
  stacker, nor before a killed consonant. With `dictionary: true`, as the
  dictionaries' words.

- Quotation marks by language (FEAT-tlp95q): `quotationMarks(language)`
  gives a BCP 47 tag's `QuotationMarks` (outer and inner pairs) from
  CLDR 48.2's delimiters, the locale found by its likely script, CLDR's
  parent locales and the `nonlikelyScript` rule, as ICU 78.3 finds it
  (every CLDR locale and its languages with 20 regions and 6 scripts
  against `ulocdata_getDelimiter`). CLDR's data is vendored in
  `vendor/cldr/48.2.0` under the Unicode License v3.

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
