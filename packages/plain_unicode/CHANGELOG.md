# Changelog

## 0.1.0-dev (unreleased)

- The Unicode Bidirectional Algorithm (UAX #9, Unicode 18.0.0):
  `BidiText`, each code unit's embedding level in its paragraph (the
  base direction given, or the first strong character's), a line's
  levels with its trailing whitespace set back (L1) and its runs or
  characters in visual order (L2); explicit embeddings, overrides and
  isolates, and bracket pairs (N0). It passes BidiTest.txt and
  BidiCharacterTest.txt. The Bidi_Class, Bidi_Mirroring_Glyph and
  Joining_Type properties (`bidiClass`, `bidiMirror`, `joiningType`),
  generated from the Unicode data.
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
