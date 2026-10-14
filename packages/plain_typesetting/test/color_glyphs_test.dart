// Color glyphs read and painted (plain_fonts' ColorGlyphs) as HarfBuzz
// 14.6.0 paints them, without the oracle: what the native oracle's
// --paint wrote for some glyphs of the color test fonts
// (harfbuzz_color_test.dart compares every glyph with it live).
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

import 'color_recorder.dart';

ColorGlyphs _colors(String font) =>
    OpenTypeFont.parse(File('test/fonts/$font').readAsBytesSync()).colorGlyphs!;

void main() {
  test('glyphs of the color test fonts: layers, every paint format, the '
      'extend modes, clip boxes, bitmaps (CBDT, sbix and a dupe)', () {
    final differ = <String>[];
    final fonts = <String, ColorGlyphs>{};
    for (final line in File(
      'test/fixtures/color_paint.txt',
    ).readAsLinesSync()) {
      if (line.startsWith('#')) continue;
      final [key, harfbuzz] = line.split('\t');
      final [font, glyph] = key.split(' ');
      final ours = recordPaint(fonts[font] ??= _colors(font), int.parse(glyph));
      if (ours != harfbuzz) {
        differ.add('$key\n  ours: $ours\n  HarfBuzz: $harfbuzz');
      }
    }
    expect(differ, isEmpty, reason: differ.take(3).join('\n'));
  });

  test("the second palette, clip boxes and bitmaps' extents", () {
    final colors = _colors('colr-test.ttf');
    expect(
      recordPaint(colors, 5, palette: 1),
      'F 2 0:333333ff | F 3 0:808080ff | F 4 1:000000ff',
    );
    expect(_colors('notocolrv1-subset.ttf').clipBoxOf(9), (
      xMin: 352,
      yMin: -32,
      xMax: 928,
      yMax: 736,
    ));
    expect(_colors('sbix-test.ttf').bitmapExtents(36)?.top, 2029);
  });

  test('a font without color glyphs has none', () {
    final font = OpenTypeFont.parse(
      File('test/fonts/notoserif-scripts.ttf').readAsBytesSync(),
    );
    expect(font.colorGlyphs, isNull);
  });
}
