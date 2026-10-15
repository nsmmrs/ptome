// Color glyphs painted as HarfBuzz 14.6.0 paints them
// (`hb_font_paint_glyph_or_fail`, the native oracle's --paint): every
// glyph of the color test fonts, the same operations in the same order
// with the same numbers. COLR version 1 (Noto Color Emoji's COLRv1 build,
// and colr-test.ttf's every paint format), version 0 (colr-test.ttf's
// layers), CBDT (Noto Color Emoji) and sbix (sbix-test.ttf). HarfBuzz's
// answers are frozen in test/frozen/harfbuzz_color.json
// (test/support/frozen.dart; FROZEN=record asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

import 'color_recorder.dart';
import 'support/frozen.dart';

const String _native = 'tool/oracles/harfbuzz-native/hb-oracle';

/// The oracle, which its answers depend on.
const String _oracle = 'HarfBuzz 14.6.0';

void main() {
  final frozen = Frozen('harfbuzz_color');
  for (final font in [
    'notocolrv1-subset.ttf',
    'colr-test.ttf',
    'notocoloremoji-subset.ttf',
    'sbix-test.ttf',
  ]) {
    test('every glyph of $font painted as HarfBuzz paints it', () {
      final path = 'test/fonts/$font';
      final bytes = File(path).readAsBytesSync();
      final parsed = OpenTypeFont.parse(bytes);
      final colors = parsed.colorGlyphs!;
      final glyphs = [for (var g = 0; g < parsed.numGlyphs; g++) g];
      final theirs = frozen
          .json<List<Object?>>(
            font,
            inputs: [_oracle, bytes],
            oracle: () {
              final r = Process.runSync('sh', [
                '-c',
                r'font="$1"; shift; printf "%s\n" "$@" | "$0" --paint "$font"',
                _native,
                path,
                ...glyphs.map((g) => '$g'),
              ]);
              return '${r.stdout}'.split('\n')..removeLast();
            },
          )
          .cast<String>();
      final ours = [for (final g in glyphs) recordPaint(colors, g)];
      final differ = <String>[];
      for (var g = 0; g < glyphs.length; g++) {
        if (ours[g] != theirs[g]) {
          differ.add(
            'glyph $g\n    ours:     ${ours[g]}\n    HarfBuzz: ${theirs[g]}',
          );
        }
      }
      expect(differ, isEmpty, reason: differ.take(3).join('\n'));
      expect(ours.where((o) => o != '-'), isNotEmpty);
    });
  }
}
