# plain_typesetting

Typesetting in pure Dart, independent of the output format. It lays out
text and pages and draws them on a `Canvas`; a backend implements the
canvas, its pages and its fonts
([plain_pdf](https://github.com/nsmmrs/ptome/tree/master/packages/plain_pdf)
for PDF).

- **Fonts and shaping.** `Font` is what layout needs from a font: metrics,
  coverage and shaping. `OpenTypeShaper` sets text in an OpenType font
  (read by plain_fonts): each character's glyph, the single substitutions
  of the features asked for (`onum`, `smcp`...), `liga` ligatures, and
  kerning by GPOS pairs or the `kern` table.
- **Paragraphs.** Inline content (text runs with colors, links, anchors,
  underlines and backgrounds; inline images) becomes the boxes, glue and
  penalties of Knuth and Plass's model. Break opportunities come from UAX
  #14 (plain_unicode) and a `Hyphenator`, and a `LineBreaker` chooses the
  breaks: first fit, Knuth-Plass, or your own.
- **Pages.** `FlowLayout` lays a tree of boxes (blocks, paragraphs,
  images, tables, columns, floats, notes, custom content) out on pages
  from `PageTemplate`s, with orphans and widows, keeps, page breaks,
  running headers and footers, anchors and marks, and lays out again only
  from what changed. `render` adds the pages to a `LayoutDocument`.
- **Math.** `MathLayout` sets a plain_math tree by the rules of the
  OpenType MATH table: scripts, fractions, radicals, stretchy delimiters,
  large operators, accents, tables and spacing.

```dart
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

final font = OpenTypeShaper(
  OpenTypeFont.parse(File('NotoSerif-Regular.ttf').readAsBytesSync()),
);
final lines = const KnuthPlassLineBreaker().breakLines(
  Paragraph([
    TextRun('A paragraph of text to break into lines.', TextStyle(font, 10)),
  ]),
  (line) => 120, // the width of each line, in points
);
// Draw each line on any Canvas: line.paint(canvas, x, top).
```

Tests lay out paragraphs, pages and formulas on a recording canvas, and
compare the shaper with HarfBuzz: every run of the test text, with
ligatures and kerning on and off and the `onum` and `smcp` features,
shapes as HarfBuzz shapes it in four fonts; and each script's sample lines
(`test/fixtures/scripts`) shape as HarfBuzz 14.6.0 shapes them in subset
Noto fonts. HarfBuzz's answers are recorded in `test/oracles`, so the tests
need no oracle installed; `ORACLES=record dart test` asks it again, with
harfbuzzjs (`tool/oracles/setup.sh`) and a full HarfBuzz build
(`tool/oracles/harfbuzz-native/setup.sh`) installed.
plain_pdf's tests set the same layouts in PDF, byte for byte against
golden files.

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, whose PDF converter lays out with it.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The shaper follows HarfBuzz's (its
features, their order and its Arabic shaper's rules), under HarfBuzz's
"Old MIT" licence: see [vendor/harfbuzz/COPYING](vendor/harfbuzz/COPYING).
The shapers' category tables are generated from HarfBuzz 14.6.0's
(`tool/harfbuzz_tables.dart`), the vowel constraints from Microsoft's
Universal Shaping Engine data under its MIT licence
([vendor/harfbuzz/ms-use/COPYING](vendor/harfbuzz/ms-use/COPYING)).
