# Unicode Character Database 18.0.0

From https://www.unicode.org/Public/18.0.0/ucd/, for
`tool/generate_line_break.dart` (which writes
`lib/src/line_break_data.g.dart`):

- `LineBreak.txt`: the Line_Break property (UAX #14).
- `EastAsianWidth.txt`: East_Asian_Width, for the `$EastAsian` set of the
  rules.
- `extracted/DerivedGeneralCategory.txt` (as `DerivedGeneralCategory.txt`):
  General_Category, for Pi, Pf, Mn, Mc and Cn.
- `emoji/emoji-data.txt` (as `emoji-data.txt`): Extended_Pictographic.

For `tool/generate_bidi.dart` (which writes `lib/src/bidi_data.g.dart`):

- `extracted/DerivedBidiClass.txt` (as `DerivedBidiClass.txt`):
  Bidi_Class, with its `@missing` defaults.
- `extracted/DerivedJoiningType.txt` (as `DerivedJoiningType.txt`):
  Joining_Type.
- `BidiBrackets.txt`: Bidi_Paired_Bracket and its type.
- `BidiMirroring.txt`: Bidi_Mirroring_Glyph.
- `ArabicShaping.txt`: the joining groups (for reference).

The conformance tests, `auxiliary/LineBreakTest.txt`, `BidiTest.txt` and
`BidiCharacterTest.txt`, are in `test/unicode/` (gzipped). Terms: `license.txt` (Unicode License
v3).
