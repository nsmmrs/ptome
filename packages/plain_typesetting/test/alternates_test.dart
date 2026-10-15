// Justification by alternative letterforms (W3C alreq 7.2.3): a justified
// line of Nastaliq takes its font's `jalt` forms at some words, none side
// by side, before its spaces widen; Gulzar's, against HarfBuzz (its
// answers recorded in test/oracles/alternates.json, test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

const String _native = 'tool/oracles/harfbuzz-native/hb-oracle';
const String _font = 'test/fonts/gulzar-subset.ttf';

/// The oracle, which its answers depend on.
const String _oracle = 'HarfBuzz 14.6.0';

final OpenTypeShaper _gulzar = OpenTypeShaper(
  OpenTypeFont.parse(File(_font).readAsBytesSync()),
);

final TextStyle _style = TextStyle(_gulzar, 20);

List<int> _ids(Line line) => [
  for (final f in line.fragments.whereType<TextFragment>())
    for (final g in f.glyphs) g.id,
];

Line _line(String text, double width, {bool alternates = true}) =>
    const KnuthPlassLineBreaker()
        .breakLines(
          Paragraph(
            [TextRun(text, _style)],
            align: TextAlign.justify,
            alignLast: TextAlign.justify,
            rightToLeft: true,
            justificationAlternates: alternates,
          ),
          (_) => width,
        )
        .single;

void main() {
  final recorded = Oracle('alternates');
  const text = 'سگ سنگ رنگ بن تن کس';

  double natural() => _style.widthOf(_style.shape(text, rightToLeft: true));

  test('a little more room: one word takes its wider forms', () {
    final plain = _style.shape(text, rightToLeft: true).map((g) => g.id);
    final wide = _ids(_line(text, natural() + 30));
    expect(wide, isNot(plain.toList()));
    expect(_ids(_line(text, natural() + 30, alternates: false)), plain);
  });

  test('none side by side, and never more than the room', () {
    final plain = _style.shape(text, rightToLeft: true);
    final (:glyphs, :gained) = justificationAlternates(
      text,
      plain,
      _style,
      1000,
      rightToLeft: true,
    );
    expect(gained, greaterThan(0));
    expect(
      _style.widthOf(glyphs),
      closeTo(_style.widthOf(plain) + gained, 1e-6),
    );
    // (The words, drawn right to left, by their glyphs: which changed.)
    List<List<int>> words(List<ShapedGlyph> glyphs) {
      final out = <List<int>>[[]];
      for (final g in glyphs) {
        if (g.text == ' ') {
          out.add([]);
        } else {
          out.last.add(g.id);
        }
      }
      return out;
    }

    final before = words(plain);
    final after = words(glyphs);
    expect(after.length, before.length);
    final changed = [
      for (var i = 0; i < before.length; i++)
        before[i].join(',') != after[i].join(','),
    ];
    expect(changed.where((c) => c).length, greaterThan(1));
    for (var i = 1; i < changed.length; i++) {
      expect(changed[i] && changed[i - 1], isFalse);
    }
    // (Less room than any word's wider forms take: none.)
    expect(
      justificationAlternates(text, plain, _style, 1, rightToLeft: true).gained,
      0,
    );
  });

  test('a font without them, or no room: as it was', () {
    final glyphs = _style.shape(text, rightToLeft: true);
    expect(
      justificationAlternates(
        text,
        glyphs,
        _style,
        0,
        rightToLeft: true,
      ).gained,
      0,
    );
  });

  test('the alternates are the forms HarfBuzz gives with jalt', () {
    final jalt = _style.copyWith(features: {'jalt'});
    for (final word in ['سگ', 'بن', 'کس', 'سنگ']) {
      final theirs = recorded
          .json<List<Object?>>(
            word,
            inputs: [_oracle, File(_font).readAsBytesSync(), word, 'jalt'],
            oracle: () {
              final r = Process.runSync('sh', [
                '-c',
                r'printf "%s\n" "$1" | "$0" "$2" jalt',
                _native,
                word,
                _font,
              ], stdoutEncoding: utf8);
              return [
                for (final g in jsonDecode((r.stdout as String).trim()) as List)
                  (g as List).first as int,
              ];
            },
          )
          .cast<int>();
      expect(
        [for (final g in jalt.shape(word, rightToLeft: true)) g.id],
        theirs,
        reason: word,
      );
    }
  });
}
