# plain_unicode

Unicode text algorithms in pure Dart, generated from the Unicode Character
Database, so they give the same results on the Dart VM and compiled to
JavaScript (whose own tables differ in age and in rules):

- **Line breaking** (UAX #14, Unicode 18.0.0): `lineBreaks(text)` lists
  the break opportunities of a text, mandatory or not, and
  `lineBreakClass(codePoint)` gives a code point's class. It passes every
  case of the conformance test, `LineBreakTest.txt`. Thai, Lao, Khmer
  and Myanmar, written without spaces, break between their words as ICU
  78.3 breaks them, from ICU's word lists (its dictionary engines'
  heuristics included; `dictionary: false` for the default rules alone).
- **Case mapping** (Unicode 17.0.0): `upperCase` and `lowerCase` map each
  code point fully, special mappings included (`ß` to `SS`, `İ` to `i̇`).
  `lowerCase(text, finalSigma: true)` applies the Final_Sigma rule, as
  JavaScript's `toLowerCase` does; without it every capital sigma becomes
  `σ`, as Ruby's `String#downcase` does. The tables match Ruby 4.0.7 and
  Node.js 26 for every code point. `language:` applies SpecialCasing's
  Turkish, Azeri and Lithuanian tailorings, as ICU does.
- **Quotation marks** (CLDR 48.2): `quotationMarks('de')` gives a
  language's outer and inner marks (`„` `“`, `‚` `‘`), the locale found
  as ICU 78.3 finds it.
- **Counter styles** (CSS Counter Styles Level 3, the W3C's Ready-made
  Counter Styles): `CounterStyle.named('hiragana').format(3)` writes a
  number in a script's numerals or letters (203 styles: `arabic-indic`,
  `hebrew`, `cjk-ideographic`, `ethiopic-numeric`...), as WeasyPrint
  writes them; `defaultNumberingSystem('ar-EG')` the digits a language
  writes its numbers in (CLDR 48.2: `arab`), `formatDigits` in them.
- **Dates** (CLDR 48.2): `formatDate(moment, 'ja')` writes a date (and
  `formatTime`, `formatDateTime` a time) as the language does, in each
  length (`DateStyle.short` to `full`), as ICU 78.3's DateFormat does in
  the Gregorian calendar.
- **Emoji** (UTS #51, Unicode 18.0.0): the emoji properties
  (`isEmojiPresentation`, `isExtendedPictographic`...) and
  `emojiSequenceLength`, where a flag, a ZWJ sequence or a keycap shown
  as an emoji starts and ends.
- **Collation** (UTS #10 with CLDR 48.2): `Collator('sv').compare(a, b)`
  and `sortKey` order text as the language does (113 tailorings and
  `-u-co-` types: `zh-u-co-stroke`, `de-u-co-phonebk`), and
  `indexLabel` gives the heading an index puts a term under (pinyin
  letters, stroke counts, kana rows), as ICU 78.3's collator and
  AlphabeticIndex do.

- **Shaping properties** (Unicode 18.0.0), for text shaping and vertical
  layout: `generalCategory`, `scriptOf` (an ISO 15924 code),
  `indicSyllabicCategory`, `indicPositionalCategory`,
  `verticalOrientation` (UAX #50), `isDefaultIgnorable`, `isMark`, and
  canonical decomposition and composition (`canonicalDecomposition`,
  `canonicalComposition`, Hangul by its algorithm). Normalized with them,
  every case of `NormalizationTest.txt` comes out as its NFD and NFC
  columns.

```dart
import 'package:plain_unicode/plain_unicode.dart';

upperCase('straße'); // 'STRASSE'
lowerCase('ΣΟΦΟΣ', finalSigma: true); // 'σοφος'
lineBreaks('Hello, world').map((b) => b.offset); // (7, 12)
Collator('sv').compare('ö', 'z'); // 1
```

Each table pins its Unicode version (`lineBreakUnicodeVersion`,
`caseMappingUnicodeVersion`, `propertiesUnicodeVersion`); the generators in `tool/` rebuild them from
the files in `vendor/ucd/`. Graphemes and normalization are left to the
`characters` and `unorm_dart` packages.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace: plain_pdf breaks lines with it, ptome maps case as Asciidoctor
(Ruby) does with it, and plain_highlighting lower-cases as highlight.js
(JavaScript) does with it.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The Unicode Character Database files in
`vendor/ucd/` and the tables generated from them are under the Unicode
License v3 (`vendor/ucd/*/license.txt`), as are CLDR's files in
`vendor/cldr/` and the tables generated from them
(`vendor/cldr/*/LICENSE`). The counter styles in `vendor/w3c/` and the
table generated from them are the W3C's, under the W3C Software and
Document License (`vendor/w3c/LICENSE`).
